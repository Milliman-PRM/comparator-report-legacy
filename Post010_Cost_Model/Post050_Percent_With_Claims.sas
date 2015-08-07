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
libname M035_Out "&M035_Out." access=readonly; 

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Aggregate claims by member, so we get all members with claims.  Limit to last 12 months.*/

%agg_claims(
	IncStart=%eval(&Date_LatestPaid. - 365)
	,IncEnd=&Date_LatestPaid.
	,PaidThru=&Date_LatestPaid.
	,Med_Rx=Med
	,Dimensions=member_id
	,Time_Slice=Last_12_Months
	,Suffix_Output=member
	)

proc sql noprint;
	create table no_mem_w_claims as
	select count(*) as Numerator
	into :num_members_with_claims
	from agg_claims_med_member;
quit;

%put Number of Members With Claims = &num_members_with_claims.;

/*Now get the number of members.*/

proc sql noprint;
	create table no_members as
	select count(*) as Denominator
	into :num_members
	from M035_out.Member
	where assignment_indicator = 'Y';
quit;

%put Number of Members = &num_members.;

proc sql noprint;
	create table percent_members_w_claims as
	select &num_members_with_claims. as members_with_claims, 
		   &num_members. as members,
		   calculated members_with_claims / calculated members as percent;
quit;






