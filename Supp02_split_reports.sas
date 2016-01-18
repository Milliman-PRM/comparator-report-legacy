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
libname M018_Out "&M018_Out.";
libname M020_Out "&M020_Out.";
libname M035_Out "&M035_Out.";
libname M073_Out "&M073_Out.";
libname M180_Out "&M180_Out.";


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/



proc import datafile = "\\indy-syn01.milliman.com\prm_phi\PHI\0273NYP\NewYorkMillimanShare\Market Level Reporting\INOVA\A2530_MSSP_Att&Markets_2Q2015.xlsx"
	out = splits
	dbms = xlsx
	replace;
run;

data Group_1 (keep = Market_A_InovaRegion rename = (Market_A_InovaRegion = Member_id))
	 Group_2 (keep = Market_B_InovaTINs rename = (Market_B_InovaTINs = Member_id))
	 Group_3 (keep = Market_C_HCIPA rename = (Market_C_HCIPA = Member_id))
	 Group_4 (keep = Market_D_ValleyRegion rename = (Market_D_ValleyRegion = Member_id))
	 Group_5 (keep = Market_E_VPE rename = (Market_E_VPE = Member_id));
	set splits;

	if Market_A_InovaRegion ne "" then do;
		label Market_A_InovaRegion = Member_id;
		output Group_1;
	end;

	if Market_B_InovaTINs ne "" then do;
		label Market_B_InovaTINs = Member_id;
		output Group_2;
	end;

	if Market_C_HCIPA ne "" then do;
		label Market_C_HCIPA = Member_id;
		output Group_3;
	end;

	if Market_D_ValleyRegion ne "" then do;
		label Market_D_ValleyRegion = Member_id;
		output Group_4;
	end;

	if Market_E_VPE ne "" then do;
		label Market_E_VPE = Member_id;
		output Group_5;
	end;

run;

%macro combo_members(number);
proc sql;
	create table Combo_&number. as
	select
		xref.crnt_hic_num as Member_id
	from Group_&number. as base
	inner join M020_Out.CCLF9_bene_xref as xref
	on base.Member_id = xref.prvs_hic_num
	union
	select
		xref.prvs_hic_num as Member_id
	from Group_&number. as base
	inner join M020_Out.CCLF9_bene_xref as xref
	on base.Member_id = xref.crnt_hic_num
	union
	select
		base.Member_id
	from Group_&number. as base
	;
quit;

%mend combo_members;

%combo_members(1);
%combo_members(2);
%combo_members(3);
%combo_members(4);
%combo_members(5);


/*Create complete copies of all of the needed tables and outputs*/
%macro copy_originals(table);
data &table._all;
	set &table.;
run;

%mend copy_originals;

%copy_originals(M073_Out.outclaims_prm);
%copy_originals(M073_Out.outpharmacy_prm);
%copy_originals(M073_Out.decor_case);
%copy_originals(M035_Out.member_time);
%copy_originals(M035_Out.member);
%copy_originals(M035_Out.member_raw_stack);
%copy_originals(M018_Out.client_member_time);

/*Create a new table with just the needed population*/
%macro create_limited(table,group,field = member_id);
proc sql;
	create table &table. as
	select
		base.*
	from &table._all as base
	where base.&field. in(
			 select member_id
			 from &group.)
	;
quit;

%mend create_limited;

%create_limited(M073_Out.outclaims_prm,Combo_1);
%create_limited(M073_Out.outpharmacy_prm,Combo_1);
%create_limited(M073_Out.decor_case,Combo_1);
%create_limited(M035_Out.member_time,Combo_1);
%create_limited(M035_Out.member,Combo_1);
%create_limited(M035_Out.member_raw_stack,Combo_1,field = bene_hic_num);
%create_limited(M018_Out.client_member_time,Combo_1);

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

%put System Return Code = &syscc.;
