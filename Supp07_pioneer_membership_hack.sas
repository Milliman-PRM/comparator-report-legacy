/*
### CODE OWNERS: Jack Leemhuis

### OBJECTIVE:
  Hack the 035_staging_membership module to limit pioneer membership to before 2016

### DEVELOPER NOTES:
	
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

%AssertThat(&Claims_Elig_Format.,eq,CCLF,ReturnMessage=The claims and eligibility format selected in the driver is not compatible with this program,FailAction=EndActiveSASSession);

/* Libnames */
libname M035_Out "&M035_Out.";
libname log "&path_onboarding_logs.";

%let dlp_cutoff = %sysfunc(mdy(1,1,2016));

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Make copies of original membership data for preservation*/

data m035_out.orig_member;
	set m035_out.member;
run;

data m035_out.orig_member_time;
	set m035_out.member_time;
run;

data m035_out.orig_member_raw_stack;
	set m035_out.member_raw_stack;
run;

/*Now rebuild the member and member time tables*/

%RunProductionPrograms(
		dir_program_src=&M035_Cde.CCLF\
		,dir_log_lst_output=&path_onboarding_logs.
		,name_python_environment=&python_environment.
		,library_process_log=log
		,bool_notify_success=False
		,prefix_program_name=Prod
		,keyword_whitelist=Prod02_Member.sas~Prod03_Member_Time.sas
		,list_cc_email=%sysfunc(ifc("%upcase(&launcher_email_cclist.)" ne "ERROR"
				,&launcher_email_cclist.
				,%str()
				))
		,prefix_email_subject=PRM Notification:
		)

/*Write member and member time tables to out directory*/

%RunProductionPrograms(
		dir_program_src=&M035_Cde.zzz_Wrapup\
		,dir_log_lst_output=&path_onboarding_logs.
		,name_python_environment=&python_environment.
		,library_process_log=log
		,bool_notify_success=False
		,prefix_program_name=Prod
		,keyword_whitelist=Prod01_Member_Indices.sas~Prod02_Validate_Outputs.sas
		,list_cc_email=%sysfunc(ifc("%upcase(&launcher_email_cclist.)" ne "ERROR"
				,&launcher_email_cclist.
				,%str()
				))
		,prefix_email_subject=PRM Notification:
		)

%put System Return Code = &syscc.;
