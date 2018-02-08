/*
### CODE OWNERS: Jason Altieri, Shea Parkes, Nathan Mytelka, Michael Menser

### OBJECTIVE:
	Use the PRM outputs to create the Admissiion/Readmission report for NYP.

### DEVELOPER NOTES:
	Indend to create a "details" table and then individual metrics.
	PQI#90 docs are here: "C:\Users\Neil.Schneider\repos\Comparator_Report\On001_Documentation\PQI_90_Prevention_Quality_Overall_Composite_.pdf"
	Original link: http://www.qualityindicators.ahrq.gov/Downloads/Modules/PQI/V50/TechSpecs/PQI_90_Prevention_Quality_Overall_Composite_.pdf
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";

/*Libnames*/
libname post008 "&post008." access=readonly;
libname post009 "&post009." access=readonly;
libname post010 "&post010." access=readonly;
libname post025 "&post025.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

%agg_claims(
		IncStart=&list_inc_start.
		,IncEnd=&list_inc_end.
		,PaidThru=&list_paid_thru.
		,Ongoing_Util_Basis=&post_ongoing_util_basis.
		,Force_Util=&post_force_util.
		,Dimensions=prm_line~caseadmitid~member_id~dischargestatus~providerID~prm_readmit_potential_yn~prm_readmit_all_cause_yn~prm_ahrq_pqi
		,Time_Slice=&list_time_period.
		,Where_Claims=%str(upcase(outclaims_prm.prm_line) eqt "I" and lowcase(outclaims_prm.prm_line) ne "i31")
		,suffix_output = inpatient
		)

%agg_claims(
		IncStart=&list_inc_start.
		,IncEnd=&list_inc_end.
		,PaidThru=&list_paid_thru.
		,Ongoing_Util_Basis=Discharge
		,Force_Util=&post_force_util.
		,Dimensions=prm_line~caseadmitid~member_id~dischargestatus~providerID~prm_readmit_potential_yn~prm_readmit_all_cause_yn~prm_ahrq_pqi
		,Time_Slice=&list_time_period.
		,Where_Claims=%str(upcase(outclaims_prm.prm_line) eqt "I" and lowcase(outclaims_prm.prm_line) ne "i31")
		,suffix_output = inpatient_disc
		)

proc sql noprint;
	select
		count(*)
	into :cnt_rows_non_days_util trimmed
	from agg_claims_med_inpatient
	where upcase(prm_util_type) ne "DAYS"
	;
quit;
%put cnt_rows_non_days_util = &cnt_rows_non_days_util.;
%AssertThat(
	&cnt_rows_non_days_util.
	,eq
	,0
	,ReturnMessage=It is assumed that all returned utilization will be of the same type and also days.
	)

data disch_xwalk;
	infile "%GetParentFolder(0)Discharge_status_xwalk.csv"
		lrecl=2048
		firstobs=2
		missover
		dsd
		delimiter=','
		;
	input
		disch_code :$2.
		disch_desc :$32.
		;
run;

/* Create claims table with discharges */
proc sql;
	create table Claims_w_Discharges as
		select claims.*,
			   disc.Discharges
		from Agg_claims_med_inpatient as claims left join agg_claims_med_inpatient_disc as disc on
			claims.time_period = disc.time_period and
			claims.prm_line = disc.prm_line and
			claims.caseadmitid = disc.caseadmitid and
			claims.member_id = disc.member_id and
			claims.dischargestatus = disc.dischargestatus and
			claims.providerID = disc.providerID and
			claims.prm_readmit_potential_yn = disc.prm_readmit_potential_yn and
			claims.prm_readmit_all_cause_yn = disc.prm_readmit_all_cause_yn and
			claims.prm_ahrq_pqi = disc.prm_ahrq_pqi
	;
quit;

/*Generate member-level unaggregated Congestive Heart Failure metrics before Rollup*/
proc sql;
	create table Heart_failure_by_member as
	select distinct
		"&name_client." as name_client
		,claims.time_slice
		,claims.member_id
		,mems.elig_status_1
		,pqi_full_desc
		,sum(discharges) as case_count
	from
		Claims_w_Discharges as claims
		inner join post008.members as mems
			on claims.Member_ID = mems.Member_ID and claims.time_slice = mems.time_period /*Limit to members in the roster*/
		left join M015_out.prm_ahrq_pqi as legend
			on claims.prm_ahrq_pqi = legend.prm_ahrq_pqi

	where
		upcase(claims.prm_ahrq_pqi) = 'PQI08'
			and
		claims.time_slice in
			(
			select max(time_slice)
			from Claims_w_Discharges
			)
	group by
		claims.time_slice
		,claims.member_id
	having
		calculated case_count > 0
	order by claims.time_slice desc
		,case_count desc
		,member_id;
quit;

/*Rollup as far as we can to support both utilization metrics and details summary.*/
/*There are some redundant columns (e.g. discharge status code and description) intentionally
  mapped on here so we can naively code gen a summary below to get details_inpatient*/
proc sql;
	create table partial_aggregation as
	select
		claims.time_slice as time_period
		,mems.elig_status_1
		,coalesce(claims.providerid,'Unknown') as prv_id_inpatient
		,claims.dischargestatus as discharge_status_code
		,coalesce(disch_xwalk.disch_desc, 'Other') as discharge_status_desc format=$256.
		,claims.prm_drg as drg_inpatient
		,claims.prm_drgversion as drg_version_inpatient
		,case
			when lowcase(claims.prm_line) not in ('i31') then 'Y'
			else 'N'
			end as acute_yn
		,case
			when lowcase(claims.prm_line) eqt 'i11' then 'Medical' 
			when lowcase(claims.prm_line) eqt 'i12' then 'Surgical'
			else 'None'
			end as medical_surgical
		,case
			when upcase(claims.prm_ahrq_pqi) in(
				'PQI01'
				,'PQI03'
				,'PQI05'
				,'PQI07'
				,'PQI08'
				,'PQI10'
				,'PQI11'
				,'PQI12'
				,'PQI13'
				,'PQI14'
				,'PQI15'
				,'PQI16'
				) then 'Y'
			else 'N'
			end as inpatient_pqi_yn
		,claims.prm_ahrq_pqi
		,case
			when claims.dischargestatus = '03' then 'Y'
			else 'N'
			end as inpatient_discharge_to_snf_yn
		,case
			when upcase(claims.prm_pref_sensitive_included_yn) eq "Y" then
				case
					when upcase(claims.prm_pref_sensitive_category) ne "NOT PSA" then "Y"
					else "N"
					end
			else "N"
			end
			as preference_sensitive_yn
		,claims.prm_pref_sensitive_category
		,claims.prm_readmit_potential_yn as inpatient_readmit_potential_yn
		,claims.prm_readmit_all_cause_yn as inpatient_readmit_yn
		,claims.prm_util as los_inpatient
		,mr_to_mcrm.mcrm_line
		,claims.prm_line /* Required for a couple metrics that exist above mcrm_line */
		,sum(claims.discharges) as cnt_discharges_inpatient
		,sum(claims.prm_util) as sum_days_inpatient
		,sum(claims.prm_costs) as sum_costs_inpatient
	from Claims_w_Discharges as claims
		inner join post008.members as mems
			on claims.Member_ID = mems.Member_ID and claims.time_slice = mems.time_period /*Limit to members in the roster*/
		left join disch_xwalk on
			claims.dischargestatus eq disch_xwalk.disch_code
		left join M015_out.link_mr_mcrm_line (where = (upcase(lob) eq "%upcase(&type_benchmark_hcg.)")) as mr_to_mcrm on
			claims.prm_line eq mr_to_mcrm.mr_line
	group by 
		time_slice
		,mems.elig_status_1
		,prv_id_inpatient
		,discharge_status_code
		,discharge_status_desc
		,drg_inpatient
		,drg_version_inpatient
		,acute_yn
		,medical_surgical
		,inpatient_pqi_yn
		,prm_ahrq_pqi
		,inpatient_discharge_to_snf_yn
		,preference_sensitive_yn
		,prm_pref_sensitive_category
		,inpatient_readmit_potential_yn
		,inpatient_readmit_yn
		,los_inpatient
		,mcrm_line
		,prm_line
	;
quit;

proc sql noprint;
	select
		name_field
	into :details_inpatient_dimensions separated by " "
	from metadata_target
	where upcase(name_table) eq "DETAILS_INPATIENT"
		and upcase(name_field) ne "NAME_CLIENT" /*Assigned later*/
		and (
			upcase(key_table) eq "Y"
			or upcase(sas_type) eq "CHAR" /*Capture duplicated code/description columns*/
			)
	order by field_position
	;
	select
		name_field
	into :details_inpatient_facts separated by " "
	from metadata_target
	where upcase(name_table) eq "DETAILS_INPATIENT"
		and upcase(name_field) ne "NAME_CLIENT" /*Assigned later*/
		and upcase(key_table) eq "N"
		and upcase(sas_type) eq "NUM"
	order by field_position
	;
quit;
%put details_inpatient_dimensions = &details_inpatient_dimensions.;
%put details_inpatient_facts = &details_inpatient_facts.;

proc means noprint nway missing data = partial_aggregation;
	class &details_inpatient_dimensions.;
	var &details_inpatient_facts.;
	output out = details_inpatient (drop = _TYPE_ _FREQ_) sum = ;
run;

/***** CALCULATE MEASURES *****/
proc sql;
    create table measures_pqi as
    select
        partial.time_period
        ,partial.elig_status_1
        ,cats(partial.PRM_ahrq_pqi, '_admits') as metric_id as metric_id format=$32. length=32
        ,catx(' ','Admits for', partial.PRM_ahrq_pqi) as metric_name
        ,sum(partial.cnt_discharges_inpatient) as metric_value
		/*,basic.memmos_sum*/
    from partial_aggregation as partial
	left join post010.basic_aggs_elig_status as basic
		on partial.time_period = basic.time_period
		and partial.elig_status_1 = basic.elig_status_1
	where partial.inpatient_pqi_yn eq 'Y'
	group by 
		partial.time_period
		,partial.elig_status_1
		,basic.memmos_sum
		,metric_id
		,metric_name
	order by 
		partial.time_period
		,partial.elig_status_1
	;
quit;

proc sql;
    create table measures_psa as
    select
        partial.time_period
        ,partial.elig_status_1
        ,lowcase(cats('psa_admits_', compress(partial.PRM_pref_sensitive_category,,'ak'))) as metric_id format=$32. length=32
        ,catx(' ', 'Admits for PSA -', partial.prm_pref_sensitive_category) as metric_name
        ,sum(partial.cnt_discharges_inpatient) as metric_value
    from partial_aggregation as partial
	left join post010.basic_aggs_elig_status as basic
			on partial.time_period = basic.time_period
			and partial.elig_status_1 = basic.elig_status_1
	where partial.preference_sensitive_yn eq 'Y'
	group by 
		partial.time_period
		,partial.elig_status_1
		,basic.memmos_sum
		,metric_id
		,metric_name
	order by 
		time_period
		,elig_status_1
	;
quit;

proc sql;
	create table measures as
	select
		detail.time_period
		,detail.elig_status_1
		,sum(case when detail.inpatient_pqi_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)
			as pqi label="PQI Combined (Chronic and Acute) Admits"

		,sum(case when detail.preference_sensitive_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)
			as pref_sens label="Preference Sensitive Admits"
		
		,sum(case when detail.los_inpatient = 1 then detail.cnt_discharges_inpatient else 0 end)
			as Num_1_Day_LOS label="Number of One Day LOSs"

		,sum(detail.cnt_discharges_inpatient)
			as Denom_1_Day_LOS label="Number of inpatient discharges"

		,sum(case when upcase(detail.medical_surgical) = 'MEDICAL' and detail.los_inpatient = 1 then detail.cnt_discharges_inpatient else 0 end)
			as Num_1_Day_LOS_Medical label="Number of Medical One Day LOSs"
			
		,sum(case when upcase(detail.medical_surgical) = 'MEDICAL' then detail.cnt_discharges_inpatient else 0 end)
			as Denom_1_day_LOS_Medical label="Number of medical inpatient discharges"

		,sum(case when detail.acute_yn = 'Y' then detail.sum_costs_inpatient else 0 end)
			/ aggs.prm_costs_sum_all_services
			as pct_acute_IP_costs label="Acute Inpatient Costs as a Percentage of Total Costs"

		,sum(case when detail.inpatient_discharge_to_snf_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)
			/ sum(detail.cnt_discharges_inpatient)
			as pct_IP_disch_to_SNF label="Percentage of IP Stays Discharged to SNF"

		,sum(case when upcase(detail.inpatient_readmit_yn) eq "Y" then detail.cnt_discharges_inpatient else 0 end)
			/ sum(case when upcase(detail.inpatient_readmit_potential_yn) eq "Y" then detail.cnt_discharges_inpatient else 0 end)
			as pct_ip_readmits label = "Percentage of IP discharges with an all cause readmission within 30 days"

		,sum(case when upcase(detail.inpatient_readmit_yn) eq "Y" then detail.cnt_discharges_inpatient else 0 end)
		 as cnt_ip_readmits label = "Number of IP discharges with an all cause readmission within 30 days"

		,sum(case when upcase(detail.inpatient_readmit_potential_yn) eq "Y" then detail.cnt_discharges_inpatient else 0 end)
			as cnt_pot_readmits label = "Number of IP discharges with the potential for readmission"

		,sum(case when detail.acute_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)
			as acute label="Acute Discharges"

		,sum(case when detail.acute_yn = 'Y' then detail.cnt_discharges_inpatient / risk.riskscr_1_util_avg else 0 end)
			as acute_riskadj label="Acute Discharges Risk Adjusted"

		,sum(case when upcase(detail.medical_surgical) = 'SURGICAL' then detail.cnt_discharges_inpatient else 0 end)
			as surgical label="Surgical Discharges"

		,sum(case when upcase(detail.medical_surgical) = 'SURGICAL' then detail.cnt_discharges_inpatient / risk.riskscr_1_util_avg else 0 end)
			as surgical_riskadj label="Surgical Discharges Risk Adjusted"

		,sum(case when upcase(detail.medical_surgical) = 'MEDICAL' then detail.cnt_discharges_inpatient else 0 end)
			as medical label="Medical Discharges"

		,sum(case when upcase(detail.medical_surgical) = 'MEDICAL' then detail.cnt_discharges_inpatient / risk.riskscr_1_util_avg else 0 end)
			as medical_riskadj label="Medical Discharges Risk Adjusted"

		,sum(case when lowcase(detail.prm_line) eq 'i11a' then detail.cnt_discharges_inpatient else 0 end)
			as medical_general label="General Medical Discharges"

		,sum(case when lowcase(detail.prm_line) eq 'i11a' then detail.cnt_discharges_inpatient / risk.riskscr_1_util_avg else 0 end)
			as medical_general_riskadj label="General Medical Discharges Risk Adjusted"

	from partial_aggregation as detail
	left join
		post010.basic_aggs_elig_status as aggs	
			on detail.time_period = aggs.time_period
			and detail.elig_status_1 = aggs.elig_status_1
	left join post009.riskscr_service as risk on
		detail.time_period eq risk.time_period
			and detail.elig_status_1 eq risk.elig_status_1
			and detail.mcrm_line eq risk.mcrm_line
	group by 
		detail.time_period
		,detail.elig_status_1
		,aggs.memmos_sum
		,aggs.prm_costs_sum_all_services
	order by
		detail.time_period
		,detail.elig_status_1
	;
quit;

proc transpose data = measures
	out = measures_long (rename = (col1 = metric_value))
	name = metric_id
	label = metric_name
	;
	by time_period elig_status_1;
run;

data post025.Heart_failure_by_mem;
	set Heart_failure_by_member;
run;
%LabelDataSet(post025.Heart_failure_by_mem)

data post025.metrics_inpatient;
	format &metrics_key_value_cgfrmt.;
	set measures_long measures_pqi measures_psa;
	by time_period elig_status_1;
	&assign_name_client.;
	metric_category = "Inpatient";
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;
%LabelDataSet(post025.metrics_inpatient)

data post025.details_inpatient;
	format &details_inpatient_cgfrmt.;
	set details_inpatient;
	&assign_name_client.;
	keep &details_inpatient_cgflds.;
run;
%LabelDataSet(post025.details_inpatient)

%put return_code = &syscc.;
