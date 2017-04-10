/*
### CODE OWNERS: Kyle Baird, Ben Copeland
  
### OBJECTIVE:
  Wrap the process execution in a single entry point for running the entire process

### DEVELOPER NOTES:
  <none>
*/
%include "%sysget(INDYHEALTH_LIBRARY_HOME)\include_sas_macros.sas" / source2;
options 
	compress = yes
	mprint
	;
%include "%sysget(ANALYTICS_PIPELINE_HOME)\010_Master\Supp01_Parser.sas" / source2;

/* Libnames */
libname M010_Log "&M010_Log.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




%RunProductionPrograms(
	dir_program_src = %sysget(MEDICARE_ACO_ONBOARDING_HOME)
	,dir_log_lst_output = &path_onboarding_logs.
	,name_python_environment = %sysget(PRM_CONDA_ENV)
	,library_process_log = M010_Log
	,bool_traverse_subdirs = True
	,bool_notify_success = False
	,prefix_program_name = Prod
	,keyword_whitelist = %sysfunc(ifc("%upcase(&launcher_onboarding_whitelist.)" ne "ERROR"
		,&launcher_onboarding_whitelist.
		,%str()
		))
	,keyword_blacklist = %sysfunc(ifc("%upcase(&launcher_onboarding_blacklist.)" ne "ERROR"
		,&launcher_onboarding_blacklist.
		,%str()
		))
	,list_cc_email = %sysfunc(ifc("%upcase(&Launcher_Email_CClist.)" ne "ERROR"
		,&Launcher_Email_CClist.
		,%str()
		))
	,prefix_email_subject = &notification_email_prefix.
	)

/***** SAS SPECIFIC FOOTER SECTION *****/
%put System Return Code = &syscc.;
