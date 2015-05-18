/*
### CODE OWNERS: Michael Menser 

### OBJECTIVE:
	Use the PRM outputs to create the Admission / Readmission report for NYP.

### DEVELOPER NOTES:
	This program creates a table with the individual metrics for ED Comparison.
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;

libname post008 "&post008." access = readonly;
libname post045 "&post045.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Create the current and prior data sets summarized at the case level (all cases, not just ED).*/
%Agg_Claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Time_Slice=&list_time_period.
	,Med_Rx=Med
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Dimensions=providerID~member_ID~prm_line~caseadmitid
	,Force_Util=&post_force_util.
    );

/*Merge the newly created table with the member roster table.  This will be the main table used for calculation of metrics.*/
proc sql;
	create table all_cases_table as
	select 
		A.*
	from agg_claims_med as A 
	inner join post008.members as B 
		on (A.time_slice = B.time_period and A.member_ID = B.member_ID)
	order by time_slice, caseadmitid;
quit;

/*Calculate the average risk score and total member months of the institution from the member roster.
  (needed for a couple of the metrics)*/
proc sql;
	create table mems_summary as
	select
		mems.time_period
		,sum(mems.memmos) as total_memmos
		,sum(mems.riskscr_1*memmos) as tot_risk_scr
	from post008.members as mems
	group by time_period
	;
quit;

/*Now limit the cases to ED cases only.*/
proc sql;
	create table ED_cases_table as
	select *
	from all_cases_table
	where prm_line = "O11a" or prm_line = "Ollb"
	;
quit;
