/*
### CODE OWNERS: Michael Menser 

### OBJECTIVE:
	This program creates a table with the individual metrics for IP Discharge Comparison.

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
libname post035 "&post035.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/
/*Create the current and prior data sets summarized at the case level (Cases with a discharge only).*/
%Agg_Claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Time_Slice=&list_time_period.
	,Med_Rx=Med
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Dimensions=member_ID~caseadmitid~DischargeStatus
	,Force_Util=&post_force_util.
	,Where_Claims = %str(PRM_Discharges = 1)
	);

/*Merge the newly created table with the member roster table.  This will be the main table used for calculation of metrics.*/
proc sql;
	create table Discharge_cases_table as
	select 
		claims.*
	from agg_claims_med as claims 
	inner join 
		post008.members as mems 
		on claims.time_slice = mems.time_period 
		and claims.member_ID = mems.member_ID

	order by 
			claims.time_slice
			,claims.caseadmitid
	;
quit;

/*Merge the newly created table with the member roster table.  This will be the main table used for calculation of metrics.*/
