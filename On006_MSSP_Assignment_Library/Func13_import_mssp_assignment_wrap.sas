/*
### CODE OWNERS: Jason Altieri, Jack Leemhuis

### OBJECTIVE:
	Run the MSSP_Assignment_Library to import and munge MSSP assignment

### DEVELOPER NOTES:
	
*/

/* Run these lines if testing interactively
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
*/

%include "&M008_cde.Func02_massage_windows.sas";
%include "%GetParentFolder(1)On005_Import_Assignment\Supp01_shared_code.sas" / source2;

/* Libnames */
libname Ref_Prod "&Path_Product_Ref." access=readonly;
libname M015_Out "&M015_Out." access=readonly;
libname M017_Out "&M017_Out.";
libname M018_Tmp "&M018_Tmp.";
libname M018_Out "&M018_Out.";
libname M020_Out "&M020_Out." access=readonly; *This is accessed out of "order";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

%let On006_cde = %GetParentFolder(1)On006_MSSP_Assignment_Library\;


%macro import_mssp_assignment_wrap();
	
	/*Run python that uses all of the assignment files*/
	libname log "&path_onboarding_logs.";	

	%RunProductionPrograms(
		dir_program_src=&On006_cde.
		,dir_log_lst_output=&path_onboarding_logs.
		,name_python_environment=&python_environment.
		,library_process_log=log
		,bool_notify_success=False
		,prefix_program_name=Func
		,keyword_whitelist=Func01_extract_mssp_assignment.py
		,list_cc_email=%sysfunc(ifc("%upcase(&launcher_email_cclist.)" ne "ERROR"
				,&launcher_email_cclist.
				,%str()
				))
		,prefix_email_subject=PRM Notification:
		)

	/*Run the functions that create macros for importing and munging assignment data*/
	%include "&On006_cde.Func02_import_raw_mssp_assignment.sas" / source2;
	%include "&On006_cde.Func03_munge_mssp_assignment.sas" / source2;
	%include "&On006_cde.Func04_munge_monthly_mssp_assignment.sas" / source2;

	/*Run func02*/
	%Import_Raw_Assignment(m017_out)

	/*Run func03*/
	%munge_mssp_assignment()

	/*Run func04*/
	%munge_monthly_mssp_assignment()

%mend;

%put System Return Code = &syscc.;
