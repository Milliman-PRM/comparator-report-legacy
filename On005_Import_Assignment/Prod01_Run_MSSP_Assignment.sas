/*
### CODE OWNERS: Jason Altieri, Jack Leemhuis

### OBJECTIVE:
	Call the MSSP import functions. 

### DEVELOPER NOTES:
	*/


options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "%GetParentFolder(1)On006_MSSP_Assignment_Library\Func12_shortcircuit-cclf-import.sas" / source2;
%include "%GetParentFolder(1)On006_MSSP_Assignment_Library\Func13_import_mssp_assignment_wrap.sas" / source2;
%include "%GetParentFolder(0)Supp01_shared_code.sas" / source2;

%AssertThat(
	%upcase(&cclf_ccr_absent_any_prior_cclf8.)
	,eq
	,INCLUDE
	,ReturnMessage=Pioneer client does not have assignment files.
	,FailAction=EndActiveSASSession
	)

%let name_datamart_src = references_client;

/* Libnames */

libname M018_Tmp "&M018_Tmp.";
libname M018_Out "&M018_Out.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Run the 020 import programs*/
%shortcircuit_cclf_import()

/*Run the assignment functions*/
%import_mssp_assignment_wrap()

/*Create metadata targets*/
%codegen_format_keep(&name_datamart_src.)


/*Update client_member/client_member_time with member address and write to out directory*/

data M018_Out.client_member (keep = &client_member_keep.);
	format &client_member_format.;
	set M018_Tmp.client_member;
run;

data M018_Out.client_member_time;
	format &client_member_time_format.;
	set M018_tmp.client_member_time;
run;

data M018_Out.client_provider (keep = &client_provider_keep.);
	format &client_provider_format.;
	set M018_tmp.client_provider;
run;


%put System Return Code = &syscc.;
