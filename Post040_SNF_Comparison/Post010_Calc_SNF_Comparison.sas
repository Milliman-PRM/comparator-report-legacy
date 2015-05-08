/*
### CODE OWNERS: Michael Menser 

### OBJECTIVE:
	Calculate the ACO Member Skilled Nursing Facility Metrics.  
    (See S:/PHI/NYP/Attachment A Core PACT Reports by Milliman for Premier.xlsx)

### DEVELOPER NOTES:
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;

libname post008 "&post008." access = readonly;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Store the start and end dates from the time windows dataset in variables for later use.*/
proc sql noprint;
	select
		time_period
		,inc_start format = 12.
		,inc_end format = 12.
		,paid_thru format = 12.
	into :time_period separated by "~"
	    ,:inc_start separated by "~"
		,:inc_end separated by "~"
		,:paid_thru separated by "~"
	from post008.Time_Windows
	;
quit;
%put time_period = &time_period.;
%put inc_start = &inc_start.;
%put inc_end = &inc_end.;
%put paid_thru = &paid_thru.;

/*Create the current and prior data sets with only SNF claims.*/
%Agg_Claims(
	IncStart=&inc_start.
	,IncEnd=&inc_end.
	,PaidThru=&paid_thru.
	,Time_Slice=&time_period.
	,Med_Rx=Med
	,Dimensions=member_ID
	,Where_Claims=outclaims_prm.prm_line eq "I31"
);

/*Output a table with only the current Agg_Claims*/
data Agg_claims_med_current (drop = time_slice);
	set Agg_claims_med;
	where time_slice = "Current";
run;

/*Find the number of distinct SNFs utilized in past 12 month period*/

/*Find the number of SNF Admissions per 1000*/
proc summary nway missing data = Agg_claims_med_current;
	vars RowCnt;
	output out = SNF_number_admissions (drop = _TYPE_ rename=(_FREQ_=num_of_mems RowCnt=num_of_adms)) sum=;
run;

data SNF_adm_per_1000 (drop = num_of_mems num_of_adms);
	set SNF_number_admissions;
	adms_per_1000 = num_of_adms / (num_of_mems / 1000);
run;
