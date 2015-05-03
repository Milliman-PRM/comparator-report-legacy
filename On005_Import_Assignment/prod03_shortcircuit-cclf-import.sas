/*
### CODE OWNERS: Shea Parkes

### OBJECTIVE:
	Import the CCLF data out of order so we have something to work from.

### DEVELOPER NOTES:
	This skips security checks because the client_* datamart hasn't been created yet.
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

/* Libnames */
libname log "&path_onboarding_logs.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




%RunProductionPrograms(
	dir_program_src=&M020_Cde.CCLF\
	,dir_log_lst_output=&M020_Log.
	,name_python_environment=&python_environment.
	,library_process_log=log
	,bool_notify_success=False
	,prefix_program_name=Prod
	,keyword_blacklist=Check_Security_Coverage
	,list_cc_email=%sysfunc(ifc("%upcase(&launcher_email_cclist.)" ne "ERROR"
			,&launcher_email_cclist.
			,%str()
			))
	,prefix_email_subject=PRM Notification:
	)

%put System Return Code = &syscc.;
