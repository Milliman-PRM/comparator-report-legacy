/*
### CODE OWNERS: Michael Menser, Aaron Hoch, Jason Altieri, Shea Parkes

### OBJECTIVE:
	Use the PRM outputs to create the Admission / Readmission report for NYP.

### DEVELOPER NOTES:
	None
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;

libname post008 "&post008." access = readonly;
libname post009 "&post009." access = readonly;
libname post010 "&post010." access = readonly;
libname post040 "&post040.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




%Agg_Claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Time_Slice=&list_time_period.
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Dimensions=providerID~member_ID~prm_line~caseadmitid
	,Force_Util=&post_force_util.
	,where_claims= %str(lowcase(outclaims_prm.prm_line) eq "i31")
	,suffix_output = snf
    );

data agg_claims_med_snf;
	set agg_claims_med_snf;

	rename Admits = Discharges;
run;

proc sql;
	create table details_SNF as
	select
		"&name_client." as name_client
		,all_snf.time_slice as time_period
		,active.elig_status_1
		,coalesce(all_snf.ProviderID,'Unknown') as prv_id_snf
		,case
			when readmits.member_id is null then 'N'
			else 'Y'
			end as snf_readmit_yn
		,all_snf.PRM_Util as los_snf
		,sum(all_snf.Discharges) as cnt_discharges_snf
		,sum(all_snf.PRM_Util) as sum_days_snf
		,sum(all_snf.PRM_Costs) as sum_costs_snf
		,sum(all_snf.discharges / risk.riskscr_1_util_avg) as _cnt_discharges_snf_riskadj
		,sum(all_snf.prm_util / risk.riskscr_1_util_avg) as _sum_days_snf_riskadj
		,sum(all_snf.prm_costs / risk.riskscr_1_cost_avg) as _sum_costs_snf_riskadj
	from agg_claims_med_snf as all_snf
	/*Limit to members active in the analysis*/
	inner join post008.members as active
		on all_snf.time_slice = active.time_period 
		and all_snf.member_ID = active.member_ID
	left join Post040.SNF_Readmissions as readmits
		on all_snf.member_id = readmits.member_id
		and all_snf.caseadmitid = readmits.caseadmitid
	left join M015_out.link_mr_mcrm_line (where = (upcase(lob) eq "%upcase(&type_benchmark_hcg.)")) as mr_to_mcrm
		on all_snf.prm_line eq mr_to_mcrm.mr_line
	left join post009.riskscr_service as risk
		on all_snf.time_slice eq risk.time_period
			and active.elig_status_1 eq risk.elig_status_1
			and mr_to_mcrm.mcrm_line eq risk.mcrm_line
	group by
		all_snf.time_slice
		,active.elig_status_1
		,prv_id_snf
		,calculated snf_readmit_yn
		,los_snf
	;
quit;



proc sql;
	create table measures as
	select
		detail.name_client
		,detail.time_period
		,detail.elig_status_1
		,"SNF" as metric_category

		,count(distinct detail.prv_id_snf) as distinct_SNFs label="Number of Distinct SNFs Utilized"

		,sum(detail.cnt_discharges_snf)
			as SNF label="SNF Discharges"

		,sum(detail._cnt_discharges_snf_riskadj)
			as SNF_rskadj label="SNF Admissions Risk Adjusted"

		,sum(detail.sum_costs_snf)
			/aggs.prm_costs_sum_all_services
			as pct_SNF_costs label="SNF Costs as a Percentage of Total Costs"

		,sum(detail.sum_days_snf)
			/sum(detail.cnt_discharges_snf)
			as alos label="SNF Average Length of Stay"

		,sum(detail.sum_costs_snf)
			/sum(detail.sum_days_snf)
			as avg_cost_per_day label="Average Cost Per Day in SNF"

		,sum(detail.sum_costs_snf)
			/sum(detail.cnt_discharges_snf)
			as avg_cost_per_discharge label="Average Cost Per SNF Discharge"

		,sum(case when detail.los_snf > 21 then detail.cnt_discharges_snf else 0 end)
			as number_SNF_over_21_days label="Count of SNF stays over 21 days"

		,sum(case when detail.snf_readmit_yn = 'Y' then detail.cnt_discharges_snf else 0 end)
			as number_SNF_readmit label="Count of SNF Discharges during an All-Cause IP Readmission Window"

	from details_snf as detail
	left join
		post010.basic_aggs_elig_status as aggs
		on detail.name_client = aggs.name_client
		and detail.time_period = aggs.time_period
		and detail.elig_status_1 = aggs.elig_status_1
	group by 
			detail.time_period
			,detail.elig_status_1
			,detail.name_client
			,aggs.memmos_sum
			,aggs.prm_costs_sum_all_services
			,aggs.memmos_sum_riskadj
	having
		sum(detail.cnt_discharges_snf) gt 0
		and sum(detail.sum_days_snf) gt 0
	;
quit;

/*Transpose the dataset to get the data into a long format*/
proc transpose data=measures
		out=metrics_transpose(rename=(COL1 = metric_value))
		name=metric_id
		label=metric_name;
	by name_client time_period metric_category elig_status_1;
run;

/*Write the tables out to the post040 library*/
data post040.details_SNF;
	format &details_SNF_cgfrmt.;
	set details_SNF;
	keep &details_SNF_cgflds.;
run;

data post040.metrics_SNF;
	format &metrics_key_value_cgfrmt.;
	set metrics_transpose;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;
%LabelDataSet(post040.metrics_SNF)

%put return_code = &syscc.;
