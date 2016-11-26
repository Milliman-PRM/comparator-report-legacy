/*
### CODE OWNERS: Anna Chen, Aaron Burgess

### OBJECTIVE:
	Call the MSSP import functions. 

### DEVELOPER NOTES:
	*/


options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "S:\PRM\PRMClient_Library\sas\mssp\shortcircuit-cclf-import.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";
%Include "&M008_Cde.Func02_massage_windows.sas" / source2;
%include "%GetParentFolder(0)Supp01_shared_code.sas" / source2;

%GetFileNamesFromDir(&path_project_received_ref., ngalign_count, NGALIGN);

%AssertThat(
	%getrecordcount(ngalign_count)
	,gt
	,0
	,ReturnMessage=Only applicable for NextGen ACOs.
	,FailAction=endactivesassession
	)

%let name_datamart_src = references_client;

/* Libnames */

libname ref_prod "&path_product_ref." access=readonly;
libname M015_Out "&M015_Out." access=readonly;
libname M017_Out "&M017_Out.";
libname M020_Out "&M020_Out." access=readonly;
libname
	%sysfunc(ifc("%upcase(&project_id_prior.)" eq "NEW"
		,M035_out "&M035_out." /*If it is a warm start stacked member rosters will be seeded here*/
		,M035_old "&M035_old." /*Otherwise, grab from prior project*/
		))
	access=readonly
	;
libname M018_Out "&M018_Out.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Run the 020 import programs*/
%shortcircuit_cclf_import()

/*Import client reference information from claims file.*/
%include "%GetParentFolder(0)Supp02_import_pioneer_info_wrap.sas" / source2;

/*Create metadata targets*/
%codegen_format_keep(&name_datamart_src.)

proc sql noprint;
	SELECT cat('20', substr(filename, 20, 2)), filename into :latest_year, :latest_file trimmed
	FROM ngalign_count
	HAVING max(substr(filename, 20, 6));
quit;

*Import assignment file. Do this because the assignment file for the two NextGen clients are in different format;
PROC IMPORT DATAFILE="&Path_Project_Received_Ref.&latest_file."
	OUT=M017_out.member_align  
	REPLACE;
	DELIMITER = "|";
	run;

*Import exclusion file;

%RunPythonScript(,%GetParentFolder(0)Supp03_extract_exclusion_file.py,,Py_code,,&path_project_logs./_Onboarding/Supp03_extract_exclusion.log,&python_environment.);
%AssertThat(&Py_code.,=,0);



%GetFileNamesfromDir(&Path_Project_Received_Ref.,ref_files,MNGREB)

proc sql noprint;
	SELECT filename into :exclu trimmed
	FROM Ref_files
	HAVING substr(filename, 26,3) eq "csv";
quit;

PROC IMPORT DATAFILE="&Path_Project_Received_Ref.&exclu."
	OUT=M017_out.nextgen_exclusion
	REPLACE;
	DELIMITER = ",";
run;

Proc SQl;
	Create Table client_member as 
		Select mem.*
			  ,coalescec(excl.reason,"") as Mem_Excluded_Reason length = 64 format = $64.
		FROM M017_out.member_align as src
		inner join M018_out.client_member (drop = Mem_Excluded_Reason) as mem 
			on src.HICN_Number_ID = mem.member_id
		left join M017_Out.nextgen_exclusion as excl
			on mem.member_id = excl.HICNO;
Quit;
   
data client_member_mod;
	set client_member;

	if Mem_Excluded_Reason = "" then assignment_indicator = "Y";
	else assignment_indicator = "N";

run;

data M018_out.client_member(keep = &client_member_keep.);
	format &client_member_format.;
	set client_member_mod;
run;

Proc SQl;
	Create Table client_member_time as 
		Select b.*
		FROM M017_out.member_align as a
		inner join M018_out.client_member_time as b
			on A.HICN_Number_ID = b.member_id;
Quit;

data client_membertime_mod;
	set client_member_time;

	if date_start ge mdy(1,1,&latest_year.) then assignment_indicator = "Y";

run;

data M018_out.client_member_time(keep = &client_member_time_keep.);
	format &client_member_time_format.;
	set client_membertime_mod;
run;

%put System Return Code = &syscc.;
