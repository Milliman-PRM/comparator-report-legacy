/*
### CODE OWNERS: Michael Menser, Aaron Hoch 

### OBJECTIVE:
	This program creates a table with the individual metrics for ED Comparison.

### DEVELOPER NOTES:
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;

libname post008 "&post008." access = readonly;
libname post010 "&post010." access = readonly;
libname post045 "&post045.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Create the current and prior data sets summarized at the case level (ED cases only).*/
%Agg_Claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Time_Slice=&list_time_period.
	,Med_Rx=Med
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Dimensions=member_ID~caseadmitid~prm_line
	,Force_Util=&post_force_util.
	,Where_Claims = %str(lowcase(outclaims_prm.prm_line) eqt "o11")
	,Suffix_Output = nyu
	);

/*Merge the newly created table with the member roster table.  This will be the main table used for calculation of metrics.*/
proc sql;
	create table ED_cases_table as
	select 
		claims.*
		,mems.elig_status_1
	from agg_claims_med_nyu as claims 
	inner join 
		post008.members as mems 
		on claims.time_slice = mems.time_period 
		and claims.member_ID = mems.member_ID

	order by 
			claims.time_slice
			,claims.caseadmitid
	;
quit;

/*Calculate the requested measures*/
proc sql;
	create table measures as
	select 
		"&name_client." as name_client
		,aggs.time_period as time_period
		,cases.elig_status_1
		,"ER" as metric_category

		,sum(PRM_Util)
			/aggs.memmos_sum * 12000
			as ED_per1k label="ED visits per 1000"

		,calculated ED_per1k
			/aggs.riskscr_1_avg
			as ED_per1k_rskadj label="ED visits per 1000 Risk Adjusted"

		,sum(cases.prm_nyu_emergent_non_avoidable * PRM_Util)
			/sum(PRM_Util)
			as ED_emer_nec label="% of ED visits Emergent Necessary (NYU logic)"

		,sum(cases.prm_nyu_emergent_avoidable * PRM_Util)
			/sum(PRM_Util)
			as ED_emer_prev label="% of ED visits Emergent Preventable (NYU logic)"

		,sum(cases.prm_nyu_emergent_primary_care * PRM_Util)
			/sum(PRM_Util)
			as ED_emer_pricare	label="% of ED visits Emergent Primary Care Treatable (NYU logic)"

		,sum(cases.prm_nyu_injury * PRM_Util)
			/sum(PRM_Util)
			as ED_injury label="% of ED visits Injury (NYU logic)"

		,sum(cases.prm_nyu_nonemergent * PRM_Util)
			/sum(PRM_Util)
			as ED_nonemer label="% of ED visits Non Emergent (NYU logic)"

		,sum(cases.prm_nyu_unclassified * PRM_Util)
			/sum(PRM_Util)
			as ED_other label="% of ED visits other (NYU logic)"

	from Ed_cases_table as cases
	left join 
		Post010.basic_aggs_elig_status as aggs
		on cases.time_slice = aggs.time_period
		and cases.elig_status_1 = aggs.elig_status_1
	group by
		name_client
		,time_period
		,cases.elig_status_1
		,metric_category
		,aggs.memmos_sum
		,aggs.riskscr_1_avg
	;
quit; 
		 
/*Transpose the dataset to get the data into a long format*/
proc transpose data=measures
		out=metrics_transpose(rename=(COL1 = metric_value))
		name=metric_id
		label=metric_name;
	by name_client time_period metric_category elig_status_1;
run;

/*Write the table out to the post045 library*/
data post045.metrics_ER;
	format &metrics_key_value_cgfrmt.;
	set metrics_transpose;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;
%LabelDataSet(post045.metrics_ER)

%put return_code = &syscc.;
