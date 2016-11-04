/*
### CODE OWNERS: Jason Altieri, Aaron Burgess

### OBJECTIVE:
	Per client request, output the member table from 035_Staging_Membership to the comparator report deliverable.
	This includes in the NewYorkMillimanShare data directory and the postboarding 050_Wrap_Up data directory.

### DEVELOPER NOTES:
	<none>
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname M035_Out "&M035_Out." access=readonly;
libname post008 "&post008." access=readonly;
libname post060 "&post060.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Output members table to NewYorkMillimanShare data directory*/

data post060.Members;
	format name_client $256.;
	set post008.members;
	&assign_name_client.;
run;

/*Write member_time to Post060 then output to NewYorkMillimanShare*/

data post060.member_time;
	set m035_out.member_time;
run;

%put System Return Code = &syscc.;
