/*
### CODE OWNERS: Sarah Prusinski

### OBJECTIVE:
	Create a Supp program that can be ran after the general process to create all of the files but split into client provided groups.

### DEVELOPER NOTES:
	

*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;

/*Libnames*/
libname M035_Out "&M035_Out.";
libname M073_Out "&M073_Out.";


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/



proc import datafile = "\\indy-syn01.milliman.com\prm_phi\PHI\0273NYP\NewYorkMillimanShare\Market Level Reporting\INOVA\A2530_MSSP_Att&Markets_2Q2015.xlsx"
	out = splits
	dbms = xlsx
	replace;
run;

data Market_A (keep = Market_A_InovaRegion rename = (Market_A_InovaRegion = Member_id))
	 Market_B (keep = Market_B_InovaTINs rename = (Market_B_InovaTINs = Member_id))
	 Market_C (keep = Market_C_HCIPA rename = (Market_C_HCIPA = Member_id))
	 Market_D (keep = Market_D_ValleyRegion rename = (Market_D_ValleyRegion = Member_id))
	 Market_E (keep = Market_E_VPE rename = (Market_E_VPE = Member_id));
	set splits;

	if Market_A_InovaRegion ne "" then do;
		label Market_A_InovaRegion = Member_id;
		output Market_A;
	end;

	if Market_B_InovaTINs ne "" then do;
		label Market_B_InovaTINs = Member_id;
		output Market_B;
	end;

	if Market_C_HCIPA ne "" then do;
		label Market_C_HCIPA = Member_id;
		output Market_C;
	end;

	if Market_D_ValleyRegion ne "" then do;
		label Market_D_ValleyRegion = Member_id;
		output Market_D;
	end;

	if Market_E_VPE ne "" then do;
		label Market_E_VPE = Member_id;
		output Market_E;
	end;

run;

/*Create complete copies of all of the needed tables and outputs*/
%macro copy_originals(table);
data &table._all;
	set &table.;
run;

%mend copy_originals;

%copy_originals(M073_Out.outclaims_prm);
%copy_originals(M073_Out.outpharmacy_prm);
%copy_originals(M035_Out.member_time_all);
%copy_originals(M035_Out.member_all);

/*Create a new table with just the needed population*/
%macro create_limited(table,group);
proc sql;
	create table &table. as
	select
		base.*
	from &table._all as base
	where base.member_id in(
			 select member_id
			 from &group.)
	;
quit;

%mend create_limited;

%create_limited(M073_Out.outclaims_prm,Market_A);
%create_limited(M073_Out.outpharmacy_prm,Market_A);
%create_limited(M035_Out.member_time_all,Market_A);
%create_limited(M035_Out.member_all,Market_A);

%RunProductionPrograms(
		/* Where the code is      */ dir_program_src          = &M030_Cde.zzz_Wrapup\
		/* Where the logs go      */ ,dir_log_lst_output      = &path_onboarding_logs.\030_HCG_Grouper_Prep
		/* Name of python env     */ ,name_python_environment = &python_environment.
		/* Where this log goes    */ ,library_process_log     = log
		/* Suppress Success Email */ ,bool_notify_success     = False
		/* Program prefix to run  */ ,prefix_program_name     = Prod
		/* Module Whitelist       */ ,keyword_whitelist       = 
		/* Module Blacklist       */ ,keyword_blacklist       = 
		/* CC'd Email Recepients  */ ,list_cc_email           = %sysfunc(ifc("%upcase(&Launcher_Email_CClist.)" ne "ERROR"
																	,&Launcher_Email_CClist.
																	,%str()
																	))
		)
