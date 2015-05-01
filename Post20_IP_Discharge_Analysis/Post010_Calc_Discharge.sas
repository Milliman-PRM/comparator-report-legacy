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

%let assign_name_client = name_client = "&name_client.";
%put assign_name_client = &assign_name_client.;

%let name_module = Post020_Discharge_Total;

%let path_dir_outputs = &path_project_data.postboarding\&name_module.\;
%put path_dir_outputs = &path_dir_outputs.;
%CreateFolder(&path_dir_outputs.)

libname M020_Out "&M020_Out.";
libname M015_Out "&M015_Out.";
libname outputs "&path_dir_outputs.";


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/
proc import out=Disc_status_codes
	datafile="S:\PHI\NYP\Reference\Discharge_Status_Codes.xlsb" 
	dbms=excel replace;
	sheet='ForSAS'; 
run;

*Create data set with only the metrics that we need and with only eligible members using the function call;
%Agg_Claims(
	IncStart=&start.
	,IncEnd=%eval(&end.-1)
	,Time_Slice=discharge
	,Med_Rx=Med
	,Dimensions=DischargeStatus
	,Where_Claims=%str(substr(outclaims_prm.prm_line,1,1) eq "I" and outclaims_prm.prm_line ne "I31")
	,Where_Elig=%str(member.Report_Status eq "Death" or member.include_in_CCR eq "Y")
);

*Calculate the total admits;
proc sql noprint;
	select sum(admits)
	into :obssum
	from Agg_claims_med_discharge;
quit;

%put sum = &obssum;

proc sql;
	CREATE TABLE Discharge_totals AS
		SELECT 
			 nest.Discharge_Desc
			,SUM(Admits) as Admits
			,SUM(Admits_pct) as Admits_pct
			,SUM(PRM_Costs) as PRM_Costs
			,ACO
		FROM (
			SELECT
				src.DischargeStatus
				,Case WHEN src.DischargeStatus = "01" THEN "Discharged to Home"
			  		  WHEN src.DischargeStatus = "62" THEN "Discharged to IRF"
			  		  WHEN src.DischargeStatus = "03" THEN "Discharged to SNF"
			  		  WHEN src.DischargeStatus = "06" THEN "Discharged to Home Health Care"
					  WHEN src.DischargeStatus = "20" THEN "Died"
			  		  ELSE "Other"
		 		 End AS Discharge_Desc
				,src.Admits
				,(src.admits / &obssum.) as Admits_pct
				,src.PRM_Costs
				,"&name_client." AS ACO

			 FROM Agg_claims_med_discharge AS src

			  ) AS NEST

		GROUP BY Discharge_Desc,ACO
;
quit;

proc transpose data = Discharge_totals
			   out = outputs.Flipped_Discharge_totals (drop = admits)
			   name = admits;
		by ACO;
		id Discharge_Desc;
run;

%LabelDataSet(outputs.Flipped_Discharge_totals)

%put System Return Code = &syscc.;


