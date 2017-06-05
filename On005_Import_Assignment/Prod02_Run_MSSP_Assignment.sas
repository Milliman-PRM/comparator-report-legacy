/*
### CODE OWNERS: Jason Altieri, Jack Leemhuis

### OBJECTIVE:
	Call the MSSP import functions. 

### DEVELOPER NOTES:
	*/

%include "%sysget(INDYHEALTH_LIBRARY_HOME)\include_sas_macros.sas" / source2;
%include "%sysget(ANALYTICS_PIPELINE_HOME)\010_Master\Supp01_Parser.sas" / source2;
%include "%sysget(PRMCLIENT_LIBRARY_HOME)sas\mssp\shortcircuit-cclf-import.sas" / source2;
%include "%sysget(PRMCLIENT_LIBRARY_HOME)sas\mssp\import_mssp_assignment_wrap.sas" / source2;

%AssertThat(
	%bquote(%upcase(&name_client.))
	,ne
	,PIONEER VALLEY ACCOUNTABLE CARE
	,ReturnMessage=NextGen has different assignment files.
	,FailAction=EndActiveSASSession
	)

%AssertThat(
	%bquote(%upcase(&name_client.))
	,ne
	,CONE HEALTH
	,ReturnMessage=NextGen has different assignment files.
	,FailAction=EndActiveSASSession
	)

%AssertThat(
	%bquote(%upcase(&name_client.))
	,ne
	,HENRY FORD
	,ReturnMessage=NextGen has different assignment files.
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

/*Member exclusion information for client member table. Conditional*/

%macro bene_exclusion();

%GetFileNamesFromDir(
	Directory = &M017_Out.
	,Output = ref_files
	,KeepStrings = bene_exclusion
	)

%if %GetRecordCount(ref_files) ne 0 %then %do;

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

data M018_Out.monthly_elig_status;
	set M018_tmp.monthly_elig_status;
run;

%put System Return Code = &syscc.;
