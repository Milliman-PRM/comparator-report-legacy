/*
### CODE OWNERS: Michael Menser

### OBJECTIVE:
	Calculate the percentage of assigned members who had at least one claim in the 12 month reporting period.

### DEVELOPER NOTES:

*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname post008 "&post008." access=readonly;
libname post010 "&post010.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

%agg_claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Med_Rx=Med
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Force_Util=&post_force_util.
	,Dimensions=member_id
	,Time_Slice=&list_time_period.
	,Suffix_Output=member
	)
