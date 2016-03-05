/*
### CODE OWNERS: Michael Menser, Anna Chen

### OBJECTIVE:
	Use the PRM outputs to create the Admission / Readmission report for NYP (Professional SNF claims only).

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
	,where_claims= %str(lowcase(outclaims_prm.prm_line) eq "p31b")
	,suffix_output = snf_professional
    );

proc sql;
	create table details_SNF_professional as
	select
		"&name_client." as name_client
		,prof_snf.time_slice as time_period
		,active.elig_status_1
		,coalesce(prof_snf.ProviderID,'Unknown') as prv_id_snf
		,sum(prof_snf.PRM_Costs) as sum_costs_prof_snf
		,sum(prof_snf.PRM_Costs / risk.riskscr_1_cost_avg) as sum_costs_prof_snf_riskadj
	from agg_claims_med_snf_professional as prof_snf
	/*Limit to members active in the analysis*/
	inner join post008.members as active
		on prof_snf.time_slice = active.time_period 
		and prof_snf.member_ID = active.member_ID
	left join M015_out.link_mr_mcrm_line (where = (upcase(lob) eq "%upcase(&type_benchmark_hcg.)")) as mr_to_mcrm
		on prof_snf.prm_line eq mr_to_mcrm.mr_line
	left join post009.riskscr_service as risk
		on prof_snf.time_slice eq risk.time_period
			and active.elig_status_1 eq risk.elig_status_1
			and mr_to_mcrm.mcrm_line eq risk.mcrm_line
	group by
		prof_snf.time_slice
		,active.elig_status_1
		,prv_id_snf
	;
quit;

proc sql;
	create table measures as
	select
		detail.name_client
		,detail.time_period
		,detail.elig_status_1
		,"SNF" as metric_category

		,count(distinct detail.prv_id_snf) as distinct_prof_SNFs label="Number of Distinct SNFs Utilized (Professional Services only)"

		,sum(detail.sum_costs_prof_snf)
			as pct_prof_SNF_costs label="Professional SNF Costs"

	from details_snf_professional as detail
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
data post040.details_SNF_professional;
	format &details_SNF_professional_cgfrmt.;
	set details_SNF_professional;
	keep &details_SNF_professional_cgflds.;
run;

data post040.metrics_SNF_professional;
	format &metrics_key_value_cgfrmt.;
	set metrics_transpose;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;
%LabelDataSet(post040.metrics_SNF_professional)

%put return_code = &syscc.;
