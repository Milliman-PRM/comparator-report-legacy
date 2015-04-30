/*
### CODE OWNERS: David Pierce, 

### OBJECTIVE:
	Find the distribution of paid percent, number of admits percent, and number of days admitted percent to 
	hospital groups for each discharge code and provider name.

### DEVELOPER NOTES:
  1) Only use beneficiaries that didn't opt out, weren't excluded, and didn't opt back in.
  2) Create "categ" for use when summarizing paid amount, number of admits, and number of days admitted by discharge code and ACO.

*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;


%let start = %sysfunc(intnx(Month,&Date_LatestPaid.,-14));
%let end = %sysfunc(intnx(Month,&Date_LatestPaid.,-2));
%let end_admits = %sysfunc(intnx(month, &end., -2, end));

%let SAS_dir = %GETPARENTFOLDER(0); *Directory that holds the SAS programs;
%let outputdir = ; *Directory of the SAS results;

libname M020_Out "&M020_Out.";
libname M015_Out "&M015_Out.";


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/
proc import out=DRG_groups
	datafile="S:\PHI\NYP\Reference\MS-DRG Crosswalk.xls" 
	dbms=excel replace;
	sheet='ForSAS'; 
run;

*Create data set with only the metrics that we need and with only eligible members using the function call;
%Agg_Claims(
	IncStart=&start.
	,IncEnd=%eval(&end.-1)
	,Time_Slice=discharge
	,Med_Rx=Med
	,Dimensions=Member_ID~prv_name~claimid~PRM_Line~PRM_DRG~PRM_FromDate~PRM_ToDate~DischargeStatus~CaseAdmitID~ICDDiag1~mem_report_hier_1
	,Where_Claims=%str(substr(outclaims_prm.prm_line,1,1) eq "I" and outclaims_prm.prm_line ne "I31")
	,Where_Elig=%str(member.Report_Status eq "Death" or member.include_in_CCR eq "Y")
);


*Merge on MPN from part a header;
data cclf1_parta_header;
	set M020_Out.cclf1_parta_header;
	format ClaimID $40.;
	ClaimID = '00'||compress(cur_clm_uniq_id)||'PTA';
run;

proc sql;
	create table elig_claims (rename = (prvdr_oscar_num=MPN)) as 
	select
		src.*
		,cclf.prvdr_oscar_num
		,drg.DRG_Description_ID
		,drg.DRG_Description
	from Agg_claims_med_discharge as src

	left join cclf1_parta_header as cclf
		on src.ClaimID = cclf.ClaimID

	left join DRG_groups as drg
		on src.PRM_DRG = drg.MS_v25 
;
quit;



**************************************************************************************************;
*Include the Discharge Status Analysis program;
%Include "&SAS_dir.Discharge Status Analysis.sas";

**************************************************************************************************;


proc sql;
	create table Combine_both_Tables as select *
		from Disch_Final_table as a left join Readm_final_table as b
		on a.prv_name = b.prv_name;
quit;

*Finally, adjust the table a little bit. Put the "Total" provider at top of the table;
data Final_all Final_others;
	set Combine_both_Tables;
	if prv_name eq "Total" then output Final_all;
	else output Final_others;
run;

*The discharges will not match between the readmission and discharge analyses b/c the readm program removed all rehab facilities and transfers;
data Final_table (drop = admsn_flag);
format prv_name admits admsn_flag readm_obs_rate readm_norm_rate Obs_Disch_to_Home Obs_Disch_to_SNF Obs_Dischto_HomeHealth_Care Obs_other_Disch
	   Norm_Disch_to_Home Norm_Disch_to_SNF Norm_Disch_to_HomeHealth_Care Norm_Other_Disch;
	set Final_all
		Final_others;
run;

proc sort data = Final_table;
by descending admits;
run;


*Export the result;
proc export data = Final_table
	outfile="&outputdir.\Facility_Discharge_Analysis.xlsx"
	dbms=excel replace;
run;



/***** SAS SPECIFIC FOOTER SECTION *****/
%put System Return Code = &syscc.;
%LogAuditing();
/*There must be a SAS Logs/Error_Check subfolder 
in the same folder as the executing program (which must be saved)
for the LogAuditing macro to save the log and lst files*/
