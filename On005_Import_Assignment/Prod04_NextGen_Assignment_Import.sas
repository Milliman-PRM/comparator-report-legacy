/*
### CODE OWNERS: Anna Chen, Aaron Burgess, Jason Altieri

### OBJECTIVE:
	Call the MSSP import functions. 

### DEVELOPER NOTES:
	*/


options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "%sysget(PRMCLIENT_LIBRARY_HOME)\sas\mssp\shortcircuit-cclf-import.sas" / source2;
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

%macro conditional_import();
	
	%if %upcase(&name_client.) eq CONE HEALTH %then %do;
      data M017_OUT.MEMBER_ALIGN    ;
        infile "&Path_Project_Received_Ref.&latest_file."
		delimiter='09'x MISSOVER DSD
 		lrecl=32767
  		firstobs=2 ;
	         informat ACO_NAME $29. ;
	         informat HICN_Number_ID $11. ;
	         informat Beneficiary_First_Name $9. ;
	         informat Beneficiary_Last_Name $10. ;
	         informat Beneficiary_Line_1_Address $27. ;
	         informat Beneficiary_Line_2_Address $21. ;
	         informat Beneficiary_Line_3_Address $1. ;
	         informat Beneficiary_Line_4_Address $1. ;
	         informat Beneficiary_Line_5_Address $1. ;
	         informat Beneficiary_Line_6_Address $1. ;
	         informat Bene_City_ID $15. ;
	         informat Bene_USPS_State_Code_ID $2. ;
	         informat Bene_Zip_5_ID $5. ;
	         informat Bene_Zip_4_ID $4. ;
	         informat BENE_SEX_CD_DESC $6. ;
	         informat Bene_Birth_Date_ID mmddyy10. ;
	         informat BENE_AGE best32. ;
	         informat Eligible_Alignment_Year_1_Switch $1. ;
	         informat Eligble_Alignment_Year_2_Switch $1. ;
	         informat MAPD_Coverage_Alignment_Year_1_S $1. ;
	         informat MAPD_Coverage_Alignment_Year_2_S $1. ;
	         informat Alignment_Year_1_HCC_Score_Numbe best32. ;
	         informat Alignment_Year_2_HCC_Score_Numbe best32. ;
	         informat New_Alignment_Beneficiary_Switch $1. ;
	         informat Provider_ACO_Alignment_By_Attest $1. ;
	         format ACO_NAME $29. ;
	         format HICN_Number_ID $11. ;
	         format Beneficiary_First_Name $9. ;
	         format Beneficiary_Last_Name $10. ;
	         format Beneficiary_Line_1_Address $27. ;
	         format Beneficiary_Line_2_Address $21. ;
	         format Beneficiary_Line_3_Address $1. ;
	         format Beneficiary_Line_4_Address $1. ;
	         format Beneficiary_Line_5_Address $1. ;
	         format Beneficiary_Line_6_Address $1. ;
	         format Bene_City_ID $15. ;
	         format Bene_USPS_State_Code_ID $2. ;
	         format Bene_Zip_5_ID $5.;
	         format Bene_Zip_4_ID $4. ;
	         format BENE_SEX_CD_DESC $6. ;
	         format Bene_Birth_Date_ID mmddyy10. ;
	         format BENE_AGE best12. ;
	         format Eligible_Alignment_Year_1_Switch $1. ;
	         format Eligble_Alignment_Year_2_Switch $1. ;
	         format MAPD_Coverage_Alignment_Year_1_S $1. ;
	         format MAPD_Coverage_Alignment_Year_2_S $1. ;
	         format Alignment_Year_1_HCC_Score_Numbe best12. ;
	         format Alignment_Year_2_HCC_Score_Numbe best12. ;
	         format New_Alignment_Beneficiary_Switch $1. ;
	         format Provider_ACO_Alignment_By_Attest $1. ;

      		 	input
	                  ACO_NAME $
	                  HICN_Number_ID $
	                  Beneficiary_First_Name $
	                  Beneficiary_Last_Name $
	                  Beneficiary_Line_1_Address $
	                  Beneficiary_Line_2_Address $
	                  Beneficiary_Line_3_Address $
	                  Beneficiary_Line_4_Address $
	                  Beneficiary_Line_5_Address $
	                  Beneficiary_Line_6_Address $
	                  Bene_City_ID $
	                  Bene_USPS_State_Code_ID $
	                  Bene_Zip_5_ID $
	                  Bene_Zip_4_ID $
	                  BENE_SEX_CD_DESC $
	                  Bene_Birth_Date_ID
	                  BENE_AGE
	                  Eligible_Alignment_Year_1_Switch $
	                  Eligble_Alignment_Year_2_Switch $
	                  MAPD_Coverage_Alignment_Year_1_S $
	                  MAPD_Coverage_Alignment_Year_2_S $
	                  Alignment_Year_1_HCC_Score_Numbe
	                  Alignment_Year_2_HCC_Score_Numbe
	                  New_Alignment_Beneficiary_Switch $
	                  Provider_ACO_Alignment_By_Attest $
				;
run;

	%end;
	%else %do;
		PROC IMPORT DATAFILE="&Path_Project_Received_Ref.&latest_file."
			OUT=M017_out.member_align  
			REPLACE;
			DELIMITER = "|";
			run;
	%end;

%mend;

%conditional_import();
	
*Import exclusion file;

/*%RunPythonScript(,%GetParentFolder(0)Supp03_extract_exclusion_file.py,,Py_code,,&path_project_logs./_Onboarding/Supp03_extract_exclusion.log,&python_environment.);
%AssertThat(&Py_code.,=,0);*/



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
		Select mem.*
				,case when excl.HICNO is not null then "Y" else "N" 
					end as excl_flag
		FROM M017_out.member_align as src
		inner join M018_out.client_member_time as mem
			on src.HICN_Number_ID = mem.member_id
		left join M017_Out.nextgen_exclusion as excl
			on src.HICN_Number_ID = excl.HICNO;
Quit;

data client_membertime_mod;
	set client_member_time;

	if (date_start ge mdy(1,1,&latest_year.) and excl_flag eq "N") then assignment_indicator = "Y";
	else assignment_indicator = "N";

run;

data M018_out.client_member_time(keep = &client_member_time_keep.);
	format &client_member_time_format.;
	set client_membertime_mod;
run;

%put System Return Code = &syscc.;
