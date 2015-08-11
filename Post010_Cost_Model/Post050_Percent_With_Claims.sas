/*
### CODE OWNERS: Michael Menser

### OBJECTIVE:
	Add a "percentage of members who had claims in the specified time slice" metric to the key metrics table. 

### DEVELOPER NOTES:

*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname post008 "&post008." access=readonly;
libname post010 "&post010."; 

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Aggregate claims by member, so we get all members with claims.  Limit to last 12 months.*/

%agg_claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Med_Rx=Med
	,Dimensions=member_id
	,Time_Slice=&list_time_period.
	,Where_Elig=(member.assignment_indicator = 'Y')
	,Suffix_Output=member
	)

proc sql noprint;
	create table perc_claims_measures as
	select
		members.time_period
		,members.elig_status_1
		,(sum(case when claims.member_id = '' then 0 else 1 end)) / (count(members.member_id)) 
			as percent_members_w_claims label="Percentage of Members with Claims"

	from Post008.members as members 
	left join agg_claims_med_member as claims
		on members.member_id = claims.member_id and
		   members.time_period = claims.time_slice
	group by
		members.time_period
		,members.elig_status_1
	order by
		members.time_period
		,members.elig_status_1
	;
quit;
		 
proc transpose data = perc_claims_measures
	out = perc_claims_measures_long (rename = (col1 = metric_value))
	name = metric_id
	label = metric_name
	;
	by time_period elig_status_1;
run;

data post010.metrics_claims_percentage;
	format &metrics_key_value_cgfrmt.;
	set perc_claims_measures_long;
	by time_period elig_status_1;
	&assign_name_client.;
	metric_category = "Basic";
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%LabelDataSet(post010.metrics_claims_percentage)

%put System Return Code = &syscc.;





