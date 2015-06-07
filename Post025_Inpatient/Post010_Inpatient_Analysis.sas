/*
### CODE OWNERS: Jason Altieri, Shea Parkes

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
		,Dimensions=prm_line~caseadmitid~member_id~dischargestatus~providerID~prm_readmit_all_cause_yn~prm_ahrq_pqi
		,Time_Slice=&list_time_period.
		,Where_Claims=%str(upcase(outclaims_prm.prm_line) eqt "I" and lowcase(outclaims_prm.prm_line) ne "i31")
		,suffix_output = inpatient
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

/*Rollup as far as we can to support both utilization metrics and details summary.*/
/*There are some redundant columns (e.g. discharge status code and description) intentionally
  mapped on here so we can naively code gen a summary below to get details_inpatient*/
proc sql;
	create table partial_aggregation as
	select
		"&name_client." as name_client
		,claims.time_slice as time_period
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
		,claims.prm_readmit_all_cause_yn as inpatient_readmit_yn
		,claims.prm_util as los_inpatient
		,mr_to_mcrm.mcrm_line
		,sum(claims.discharges) as cnt_discharges_inpatient
		,sum(claims.prm_util) as sum_days_inpatient
		,sum(claims.prm_costs) as sum_costs_inpatient
	from agg_claims_med_inpatient as claims
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
		,inpatient_discharge_to_snf_yn
		,preference_sensitive_yn
		,inpatient_readmit_yn
		,los_inpatient
		,mcrm_line
	;
quit;

proc sql noprint;
	select
		name_field
	into :details_inpatient_dimensions separated by " "
	from metadata_target
	where upcase(name_table) eq "DETAILS_INPATIENT"
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
/*** Non-Risk Adjusted ***/
proc sql;
	create table measures_non_riskadj as
	select
		detail.name_client
		,detail.time_period
		,detail.elig_status_1
		,sum(case when detail.inpatient_pqi_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)
			/ aggs.memmos_sum * 12000
			as pqi_per1k label="PQI Combined (Chronic and Acute) Admits per 1000"

		,sum(case when detail.preference_sensitive_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)
			/ aggs.memmos_sum * 12000
			as pref_sens_per1k label="Preference Sensitive Admits per 1000"

		,sum(case when detail.los_inpatient = 1 then detail.cnt_discharges_inpatient else 0 end)
			/ sum(detail.cnt_discharges_inpatient)
			as pct_1_day_LOS label="One Day LOS as a Percent of Total Discharges"

		,sum(case when upcase(detail.medical_surgical) = 'MEDICAL' and detail.los_inpatient = 1 then detail.cnt_discharges_inpatient else 0 end)
			/ sum(case when upcase(detail.medical_surgical) = 'MEDICAL' then detail.cnt_discharges_inpatient else 0 end)
			as pct_1_day_LOS_medical label="One Day LOS as a Percent of Medical Discharges"

		,sum(case when detail.acute_yn = 'Y' then detail.sum_costs_inpatient else 0 end)
			/ aggs.prm_costs_sum_all_services
			as pct_acute_IP_costs label="Acute Inpatient Costs as a Percentage of Total Costs"

		,sum(case when detail.inpatient_discharge_to_snf_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)
			/ sum(detail.cnt_discharges_inpatient)
			as pct_IP_disch_to_SNF label="Percentage of IP Stays Discharged to SNF"

		,sum(case when upcase(detail.inpatient_readmit_yn) eq "Y" then detail.cnt_discharges_inpatient else 0 end)
			/ sum(detail.cnt_discharges_inpatient)
			as pct_ip_readmits label = "Percentage of IP discharges with an all cause readmission within 30 days"
	from details_inpatient as detail
	left join
		post010.basic_aggs_elig_status as aggs	
			on detail.name_client = aggs.name_client
			and detail.time_period = aggs.time_period
			and detail.elig_status_1 = aggs.elig_status_1
	group by 
		detail.time_period
		,detail.name_client
		,detail.elig_status_1
		,aggs.memmos_sum
		,aggs.prm_costs_sum_all_services
		,aggs.memmos_sum_riskadj
	order by
		detail.name_client
		,detail.time_period
		,detail.elig_status_1
	;
quit;

/*** Risk Adjusted ***/
proc sql;
	create view cost_util_riskadj_mcrm as
	select
		claims_agg_mcrm.*
		,risk.riskscr_1_util_avg
		,risk.riskscr_1_cost_avg
		,claims_agg_mcrm.cnt_discharges_medical / risk.riskscr_1_util_avg as cnt_discharges_medical_riskadj
		,claims_agg_mcrm.cnt_discharges_surgical / risk.riskscr_1_util_avg as cnt_discharges_surgical_riskadj
		,claims_agg_mcrm.cnt_discharges_acute / risk.riskscr_1_util_avg as cnt_discharges_acute_riskadj
		,claims_agg_mcrm.cnt_discharges / risk.riskscr_1_util_avg as cnt_discharges_riskadj
		,claims_agg_mcrm.sum_days / risk.riskscr_1_util_avg as sum_days_riskadj
		,claims_agg_mcrm.sum_costs / risk.riskscr_1_cost_avg as sum_costs_riskadj
	from (
		select
			name_client
			,time_period
			,elig_status_1
			,mcrm_line
			/*Flatten here to avoid having to repeat this nasty set of case logic
			  again on risk adjusted values*/
			,sum(
				case upcase(medical_surgical)
					when "MEDICAL" then cnt_discharges_inpatient
					else 0
					end
				) as cnt_discharges_medical
			,sum(
				case upcase(medical_surgical)
					when "SURGICAL" then cnt_discharges_inpatient
					else 0
					end
				) as cnt_discharges_surgical
			,sum(
				case upcase(acute_yn)
					when "Y" then cnt_discharges_inpatient
					else 0
					end
				) as cnt_discharges_acute
			,sum(cnt_discharges_inpatient) as cnt_discharges
			,sum(sum_days_inpatient) as sum_days
			,sum(sum_costs_inpatient) as sum_costs
		from partial_aggregation
		group by
			name_client
			,time_period
			,elig_status_1
			,mcrm_line
		) as claims_agg_mcrm
	left join post009.riskscr_service as risk on
		claims_agg_mcrm.time_period eq risk.time_period
			and claims_agg_mcrm.elig_status_1 eq risk.elig_status_1
			and claims_agg_mcrm.mcrm_line eq risk.mcrm_line
	;
quit;

proc means noprint nway missing data = cost_util_riskadj_mcrm;
	class name_client time_period elig_status_1;
	var cnt_: sum_:;
	output out = cost_util_riskadj (drop = _TYPE_ _FREQ_) sum = ;
run;

proc sql;
	create table measures_riskadj as
	select
		cost_util.name_client
		,cost_util.time_period
		,cost_util.elig_status_1
/*		,basic_aggs.memmos_sum*/
		,cost_util.cnt_discharges_medical / basic_aggs.memmos_sum * 12 * 1000 as medical_per1k label="Medical Discharges per 1000"
		,cost_util.cnt_discharges_surgical / basic_aggs.memmos_sum * 12 * 1000 as surgical_per1k label="Surgical Discharges per 1000"
		,cost_util.cnt_discharges_acute / basic_aggs.memmos_sum * 12 * 1000 as acute_per1k label="Acute Discharges per 1000"

		,cost_util.cnt_discharges_medical_riskadj / basic_aggs.memmos_sum * 12 * 1000 as medical_per1k_riskadj label="Medical Discharges per 1000 Risk Adjusted"
		,cost_util.cnt_discharges_surgical_riskadj / basic_aggs.memmos_sum * 12 * 1000 as surgical_per1k_riskadj label="Surgical Discharges per 1000 Risk Adjusted"
		,cost_util.cnt_discharges_acute_riskadj / basic_aggs.memmos_sum * 12 * 1000 as acute_per1k_riskadj label="Acute Discharges per 1000 Risk Adjusted"
	from cost_util_riskadj as cost_util
	left join post010.basic_aggs_elig_status as basic_aggs on
		cost_util.name_client eq basic_aggs.name_client
			and cost_util.time_period eq basic_aggs.time_period
			and cost_util.elig_status_1 eq basic_aggs.elig_status_1
	order by
		cost_util.name_client
		,cost_util.time_period
		,cost_util.elig_status_1
	;
quit;

/*** Transpose and Stack ***/
proc transpose data = measures_riskadj
	out = measures_riskadj_long (rename = (col1 = metric_value))
	name = metric_id
	label = metric_name
	;
	by name_client time_period elig_status_1;
run;

proc transpose data = measures_non_riskadj
	out = measures_non_riskadj_long (rename = (col1 = metric_value))
	name = metric_id
	label = metric_name
	;
	by name_client time_period elig_status_1;
run;

data post025.metrics_inpatient;
	format &metrics_key_value_cgfrmt.;
	set measures_riskadj_long
		measures_non_riskadj_long
		;
	by name_client time_period elig_status_1;
	metric_category = "Inpatient";
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;
%LabelDataSet(post025.metrics_inpatient)

data post025.details_inpatient;
	format &details_inpatient_cgfrmt.;
	set details_inpatient;
	keep &details_inpatient_cgflds.;
run;
%LabelDataSet(post025.details_inpatient)

%put return_code = &syscc.;
