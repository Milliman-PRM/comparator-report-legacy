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

libname M017_Out "&M017_Out.";
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

/*Member exclusion information for client member table*/

*Set up libname to import bene exclusion xml file;
%GetFileNamesfromDir(&Path_Project_Received_Ref.,ref_files,BNEXC)

%macro bene_exclusion();

%if %GetRecordCount(ref_files) ne 0 %then %do;

proc sql noprint;
	select filename
	into :bnexc_file trimmed
	from ref_files
;
quit;

%put bnexc_file = &bnexc_file.;

filename Bene_map "%GetParentFolder(0)Bene_Excl.map";
filename Bene_Exc "&Path_Project_Received_Ref.&bnexc_file.";
libname Bene_Exc xmlv2 xmltype=xmlmap xmlmap=Bene_map;
 
data M017_Out.bene_exclusion (keep = HICN BeneExcReason);
	set Bene_Exc.bene_exclusion (rename = (BeneExcReason = BeneExcReason_pre));
	format BeneExcReason $64.;
		
		if BeneExcReason_pre eq "BD" then BeneExcReason = "Beneficiary Declined";
			else if BeneExcReason_pre eq "EC" then BeneExcReason = "Excluded by CMS";
			else if BeneExcReason_pre eq "PL" then BeneExcReason = "Participant List Change";
			else BeneExcReason = BeneExcReason_pre;

run;

data Bene_Control;
	set Bene_Exc.Bene_Control;
run;

*Check record count for the bene exclusion file against the control total;
proc sql noprint;
		select 
			RecordCount
			format= 8.
			into: Control_RecordCount
		from
			Bene_control
		;
	quit;

%put &Control_RecordCount.;

%assertthat(%GetRecordCount(M017_Out.bene_exclusion), eq, &Control_RecordCount.,ReturnMessage=Provider row counts do not match.);

*Add on member excluded reason;
proc sql;
	create table client_member_exc as
	select
		src.*
		,coalescec(excl.BeneExcReason,"") as Mem_Excluded_Reason length = 64 format = $64.
	from M018_Tmp.client_member (drop = Mem_Excluded_Reason) as src
	left join M017_Out.bene_exclusion as excl
		on src.member_id = excl.HICN
	;
quit;

data M018_Out.client_member (keep = &client_member_keep.);
	format &client_member_format.;
	set client_member_exc;
run;

%end;

%else %do;

data M018_Out.client_member (keep = &client_member_keep.);
	format &client_member_format.;
	set M018_Tmp.client_member;
run;

%end;

%mend;
%bene_exclusion;

/*Other client reference tables*/
data M018_Out.client_member_time;
	format &client_member_time_format.;
	set M018_tmp.client_member_time;
run;

data M018_Out.client_provider (keep = &client_provider_keep.);
	format &client_provider_format.;
	set M018_tmp.client_provider;
run;


%put System Return Code = &syscc.;
