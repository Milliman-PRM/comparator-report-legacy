/*
### CODE OWNERS: Sarah Prusinski, Jason Altieri

### OBJECTIVE:
	Create a Supp program that can be ran after the general process to create all of the files but split into client provided groups.

### DEVELOPER NOTES:
	

*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;

/*Libnames*/
libname M018_Out "&M018_Out.";
libname M020_Out "&M020_Out.";
libname M035_Out "&M035_Out.";
libname M073_Out "&M073_Out.";
libname M180_Out "&M180_Out.";


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/



proc import datafile = "&path_project_received_ref\Market_Splits.csv"
	out = splits
	replace;
	delimiter = ',';
	getnames = yes;
	guessingrows = 1000;
run;

proc sql noprint;
	select
		count(name)
	into :group_count

	from dictionary.columns
	where upcase(libname) eq 'WORK' and
		  upcase(memname) eq 'SPLITS'
	;
quit;

%put &=group_count.;

%macro split_groups;
	
	%do number = 1 %to &group_count.;
	
		data Group_&number (keep = Group_&number rename = (Group_&number = Member_id));
			set splits;
	
			if Group_&number ne "" then output;
		run;
	
		proc sql;
			create table Combo_&number as
			select
				xref.crnt_hic_num as Member_id
			from Group_&number as base
			inner join M020_Out.CCLF9_bene_xref as xref
			on base.Member_id = xref.prvs_hic_num
			union
			select
				xref.prvs_hic_num as Member_id
			from Group_&number as base
			inner join M020_Out.CCLF9_bene_xref as xref
			on base.Member_id = xref.crnt_hic_num
			union
			select
				base.Member_id
			from Group_&number as base
			;
		quit;
	
	%end;

%mend split_groups;

%split_groups;

/*Create complete copies of all of the needed tables and outputs*/
%macro copy_originals(table,suffix);

	data &table._&suffix.;
		set &table.;
	run;

%mend copy_originals;

%copy_originals(M073_Out.outclaims_prm,all);
%copy_originals(M073_Out.outpharmacy_prm,all);
%copy_originals(M073_Out.decor_case,all);
%copy_originals(M035_Out.member_time,all);
%copy_originals(M035_Out.member,all);
%copy_originals(M035_Out.member_raw_stack,all);
%copy_originals(M018_Out.client_member_time,all);

%RunPythonScript(,%GetParentFolder(0)Supp03_output_rename.py,,Py_code,&post050. all,&path_project_logs./_onboarding/Supp02_all.log,prod3);
%AssertThat(&Py_code.,=,0);

/*Create a new table with just the needed population*/
%macro create_limited(table,group,field = member_id);

	proc sql;
		create table &table. as
		select
			base.*
		from &table._all as base
		where base.&field. in(
				 select member_id
				 from Combo_&group.)
		;
	quit;

%mend create_limited;

/*Create a macro to loop over most of the rest of the process*/
%macro Run_Process;
	
	%do number = 1 %to &group_count.;
	
		%if %GetRecordCount(Combo_&number) ne 0 %then %do;
	
			%create_limited(M073_Out.outclaims_prm,&number);
			%create_limited(M073_Out.outpharmacy_prm,&number);
			%create_limited(M073_Out.decor_case,&number);
			%create_limited(M035_Out.member_time,&number);
			%create_limited(M035_Out.member,&number);
			%create_limited(M035_Out.member_raw_stack,&number,field = bene_hic_num);
			%create_limited(M018_Out.client_member_time,&number);
	
			%RunProductionPrograms(
			/* Where the code is      */ dir_program_src          = &path_onboarding_code.
			/* Where the logs go      */ ,dir_log_lst_output      = &path_onboarding_logs.
			/* Name of python env     */ ,name_python_environment = &python_environment.
			/* Where this log goes    */ ,library_process_log     = 
			/* Scrape subfolders      */ ,bool_traverse_subdirs   = True
			/* Suppress Success Email */ ,bool_notify_success     = False
			/* Program prefix to run  */ ,prefix_program_name     = Post
			/* Onboarding Whitelist   */ ,keyword_whitelist       = %sysfunc(ifc("%upcase(&launcher_onboarding_whitelist.)" ne "ERROR"
																		,&launcher_onboarding_whitelist.
																		,%str()
																		))
			/* Onboarding Blacklist   */ ,keyword_blacklist       = %sysfunc(ifc("%upcase(&launcher_onboarding_blacklist.)" ne "ERROR"
																		,%sysfunc(cat(&launcher_onboarding_blacklist.,~Post050_output_deliverable))
																		,Post050_output_deliverable
																		))
			/* CC'd Email Recepients  */ ,list_cc_email           = %str()
			/* Email Subject Prefix   */ ,prefix_email_subject    = PRM Notification:
			)
	
			%copy_originals(M073_Out.outclaims_prm,&number);
			%copy_originals(M073_Out.outpharmacy_prm,&number);
			%copy_originals(M073_Out.decor_case,&number);
			%copy_originals(M035_Out.member_time,&number);
			%copy_originals(M035_Out.member,&number);
			%copy_originals(M035_Out.member_raw_stack,&number);
			%copy_originals(M018_Out.client_member_time,&number);
	
			%RunPythonScript(,%GetParentFolder(0)Supp03_output_rename.py,,Py_code,&post050. &number,&path_project_logs.\_onboarding\Supp02_&number.log,prod3);
			%AssertThat(&Py_code.,=,0);
	
		%end;
	
	%end;

%mend Run_Process;

%Run_Process;

/*Return the combined version of the various tables to the non-underscored form*/
%macro return_originals(table);

	data &table.;
		set &table._all;
	run;

%mend return_originals;

%return_originals(M073_Out.outclaims_prm);
%return_originals(M073_Out.outpharmacy_prm);
%return_originals(M073_Out.decor_case);
%return_originals(M035_Out.member_time);
%return_originals(M035_Out.member);
%return_originals(M035_Out.member_raw_stack);
%return_originals(M018_Out.client_member_time);

%put System Return Code = &syscc.;

