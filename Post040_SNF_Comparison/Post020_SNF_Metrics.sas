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
    );


proc sql;
	create table details_SNF as
	select
		"&name_client." as name_client
		,all_snf.time_slice as time_period
		,all_snf.ProviderID as prv_id_snf
		,case
			when readmits.member_id is null then 'N'
			else 'Y'
			end as snf_readmit_yn
		,all_snf.PRM_Util as los_snf
		,sum(all_snf.Discharges) as cnt_discharges_snf
		,sum(all_snf.PRM_Util) as sum_days_snf
		,sum(all_snf.PRM_Costs) as sum_costs_snf
	from agg_claims_med as all_snf
	/*Limit to members active in the analysis*/
	inner join post008.members as active
		on all_snf.time_slice = active.time_period 
		and all_snf.member_ID = active.member_ID
	left join Post040.SNF_Readmissions as readmits
		on all_snf.member_id = readmits.member_id
		and all_snf.time_slice = readmits.time_slice
		and all_snf.caseadmitid = readmits.caseadmitid
	group by
		all_snf.time_slice
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
		,"SNF" as metric_category

		,detail.distinct_SNFs label="Number of Distinct SNFs Utilized"

		,detail.sum_discharges_snf
			/aggs.memmos_sum * 12000
			as SNF_per1k label="SNF Discharges per 1000"

		,detail.sum_discharges_snf
			/aggs.memmos_sum_riskadj * 12000
			as SNF_per1k_rskadj label="SNF Admissions per 1000 Risk Adjusted"

		,detail.sum_costs_snf
			/aggs.prm_costs_sum_all_services
			as pct_SNF_costs label="SNF Costs as a Percentage of Total Costs"

		,detail.sum_days_snf
			/detail.sum_discharges_snf
			as alos label="SNF Average Length of Stay"

		,detail.sum_costs_snf
			/detail.sum_days_snf
			as avg_cost_per_day label="Average Cost Per Day in SNF"

		,detail.sum_costs_snf
			/detail.sum_discharges_snf
			as avg_cost_per_discharge label="Average Cost Per SNF Discharge"

		,detail.sum_long_snf_discharges
			/detail.sum_discharges_snf
			as percent_SNF_over_21_days label="Percentage of SNF stays over 21 days"

		,detail.sum_snf_discharges_readmit
			/detail.sum_discharges_snf
			as percent_SNF_readmit label="Percentage of SNF Discharges with Actue IP Readmits Within 30 Days"

	from (
		select
			name_client
			,time_period
			,count(distinct prv_id_snf) as distinct_SNFs
			,sum(cnt_discharges_snf) as sum_discharges_snf
			,sum(sum_costs_snf) as sum_costs_snf
			,sum(sum_days_snf) as sum_days_snf
			,sum(case when los_snf > 21 then cnt_discharges_snf else 0 end) as sum_long_snf_discharges
			,sum(case when snf_readmit_yn = 'Y' then cnt_discharges_snf else 0 end) as sum_snf_discharges_readmit
		from details_SNF
		group by
			name_client
			,time_period
		)as detail
	left join
		post010.basic_aggs as aggs
		on detail.name_client = aggs.name_client
		and detail.time_period = aggs.time_period
	order by 
			detail.time_period
			,detail.name_client
	;
quit;

/*Transpose the dataset to get the data into a long format*/
proc transpose data=measures
		out=metrics_transpose(rename=(COL1 = metric_value))
		name=metric_id
		label=metric_name;
	by name_client time_period metric_category;
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

%put return_code = &syscc.;
