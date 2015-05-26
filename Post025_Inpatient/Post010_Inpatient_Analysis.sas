/*
### CODE OWNERS: Jason Altieri, Shea Parkes

### OBJECTIVE:
	Use the PRM outputs to create the Admissiion/Readmission report for NYP.

### DEVELOPER NOTES:
	Indend to create a "details" table and then individual metrics.
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";

/*Libnames*/
libname post008 "&post008." access=readonly;
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

proc sql;
	create table details_inpatient as
	select
		"&name_client." as name_client
		,claims.time_slice as time_period
		,claims.providerid as prv_id_inpatient
		,sum(claims.discharges) as cnt_discharges_inpatient
		,claims.dischargestatus as discharge_status_code
		,coalesce(disch_xwalk.disch_desc, 'Other') as discharge_status_desc format=$256.
		,sum(claims.prm_util) as sum_days_inpatient
		,claims.prm_util as los_inpatient
		,sum(claims.prm_costs) as sum_costs_inpatient
		,claims.prm_drg as drg_inpatient
		,claims.prm_drgversion as drg_version_inpatient
		,case
			when lowcase(claims.prm_line) not in (&nonacute_ip_prm_line_ignore_snf.) then 'Y'
			else 'N'
			end as acute_yn
		,case
			when claims.prm_line in ('I11a', 'I11b') then 'Medical' 
			when claims.prm_line = 'I12' then 'Surgical'
			else 'None'
			end as medical_surgical
		,claims.prm_readmit_all_cause_yn as inpatient_readmit_yn
		,case
			when upcase(claims.prm_ahrq_pqi) in(
				'NONE'
				,'PQI02' /* PQI02 is not part of the composite PQI score */
				) then 'N'
			else 'Y'
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
	from agg_claims_med as claims
		inner join post008.members as mems
			on claims.Member_ID = mems.Member_ID and claims.time_slice = mems.time_period /*Limit to members in the roster*/
		left join disch_xwalk on
			claims.dischargestatus eq disch_xwalk.disch_code
	group by 
		time_slice
		,prv_id_inpatient
		,discharge_status_code
		,discharge_status_desc
		,los_inpatient
		,drg_inpatient
		,drg_version_inpatient
		,acute_yn
		,medical_surgical
		,inpatient_readmit_yn
		,inpatient_pqi_yn
		,inpatient_discharge_to_snf_yn
		,preference_sensitive_yn
	;
quit;


/*Calculate the requested measures*/
proc sql;
	create table measures as
	select
		detail.name_client
		,detail.time_period
		,"Inpatient" as metric_category

		,sum(case when detail.acute_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)
			/ aggs.memmos_sum * 12000
			as acute_per1k label="Acute Discharges per 1000"

		,sum(case when detail.acute_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)
			/ aggs.memmos_sum_riskadj * 12000
			as acute_per1k_riskadj label="Acute Discharges per 1000 Risk Adjusted"

		,sum(case when upcase(detail.medical_surgical) = 'SURGICAL' then detail.cnt_discharges_inpatient else 0 end)
			/ aggs.memmos_sum * 12000
			as surgical_per1k label="Surgical Discharges per 1000"

		,sum(case when upcase(detail.medical_surgical) = 'SURGICAL' then detail.cnt_discharges_inpatient else 0 end)
			/ aggs.memmos_sum_riskadj * 12000
			as surgical_per1k_riskadj label="Surgical Discharges per 1000 Risk Adjusted"

		,sum(case when upcase(detail.medical_surgical) = 'MEDICAL' then detail.cnt_discharges_inpatient else 0 end)
			/ aggs.memmos_sum * 12000
			as medical_per1k label="Medical Discharges per 1000"

		,sum(case when upcase(detail.medical_surgical) = 'MEDICAL' then detail.cnt_discharges_inpatient else 0 end)
			/ aggs.memmos_sum_riskadj * 12000
			as medical_per1k_riskadj label="Medical Discharges per 1000 Risk Adjusted"

		,sum(case when detail.inpatient_pqi_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)
			/ aggs.memmos_sum * 12000
			as pqi_per1k label="PQI Combined (Chronic and Acute) Admits per 1000"

		,sum(case when detail.preference_sensitive_yn = 'Y' then detail.cnt_discharges_inpatient else 0 end)
			/ aggs.memmos_sum * 12000
			as pref_sens_per1k label="Preference Sensitive Admits per 1000"

		,sum(case when detail.los_inpatient = 1 then detail.cnt_discharges_inpatient else 0 end)
			/ sum(detail.cnt_discharges_inpatient)
			as pct_1_day_LOS label="One Day LOS as a Percent of Total Discharges"

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
		post010.basic_aggs as aggs	
			on detail.name_client = aggs.name_client
			and detail.time_period = aggs.time_period
	group by 
		detail.time_period
		,detail.name_client
		,aggs.memmos_sum
		,aggs.prm_costs_sum_all_services
		,aggs.memmos_sum_riskadj
	;
quit;



/*Munge to target formats*/
proc transpose data=measures 
				out=metrics_transpose(rename=(COL1 = metric_value))
				name=metric_id
				label=metric_name;
	by name_client time_period metric_category;
run;

data post025.details_inpatient;
	format &details_inpatient_cgfrmt.;
	set details_inpatient;
	keep &details_inpatient_cgflds.;
run;

data post025.metrics_inpatient;
	format &metrics_key_value_cgfrmt.;
	set metrics_transpose;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;
%LabelDataSet(post025.metrics_inpatient)

%put return_code = &syscc.;
