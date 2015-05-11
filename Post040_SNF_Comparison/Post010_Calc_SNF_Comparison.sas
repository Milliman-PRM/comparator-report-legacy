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

/*Create the current and prior data sets with only SNF claims at the case level.*/
%Agg_Claims(
	IncStart=&inc_start.
	,IncEnd=&inc_end.
	,PaidThru=&paid_thru.
	,Time_Slice=&time_period.
	,Med_Rx=Med
	,Ongoing_Util_Basis=Discharge
	,Dimensions=prm_line~caseadmitid~member_id~providerID~prv_id_npi
	,Where_Claims=outclaims_prm.prm_line eq "I31"
    );

proc sort data=agg_claims_med out=cases_med;
	by member_id date_case_latest date_case_earliest;
run;

/*Limit cases to the current time slice*/
data cases_med_current;
	set cases_med;
	where time_slice = "Current";
run;

/*Limit cases to the prior time slice*/
data cases_med_prior;
	set cases_med;
	where time_slice = "Prior";
run;
	
/*Now create the current and prior data sets with only SNF claims at the member level.*/
%Agg_Claims(
	IncStart=&inc_start.
	,IncEnd=&inc_end.
	,PaidThru=&paid_thru.
	,Time_Slice=&time_period.
	,Med_Rx=Med
	,Ongoing_Util_Basis=Discharge
	,Dimensions=member_id
	,Where_Claims=outclaims_prm.prm_line eq "I31"
    );

proc sort data=agg_claims_med out=members;
	by member_id;
run;

/*Limit members to the current time slice*/
data members_current;
	set members;
	where time_slice = "Current";
run;

/*Limit members to the prior time slice*/
data members_prior;
	set members;
	where time_slice = "Prior";
run;

/*Calculate the number of distinct SNFs for the current time slice and the prior time slice.*/
proc sql noprint;
	create table Number_NPIs_current as
	select count(distinct prv_id_npi) as NPI_Count
	from cases_med_current;
quit;
	
proc sql noprint;
	create table Number_NPIs_prior as
	select count(distinct prv_id_npi) as NPI_Count
	from cases_med_prior;
quit;

/*Find the number of SNF Admissions per 1000 for the current and prior time slice*/
proc summary nway missing data = Members_current;
	vars RowCnt;
	output out = Number_admissions_current (drop = _TYPE_ _FREQ_ rename=(RowCnt=num_of_adms)) sum=;
run;

proc summary nway missing data = Members_current;
	vars MemMos;
	output out = Total_mem_mos_current (drop = _TYPE_ _FREQ_ rename=(MemMos=Total_memmos)) sum=;
quit;

data Total_mem_k_years_current;
	set Total_mem_mos_current;
	Mem_k_years = Total_memmos / 12000;
	keep Mem_k_years;
run;

data Admissions_per_1000_current;
	merge Number_admissions_current Total_mem_k_years_current;
	Admissions_per_1000 = num_of_adms / Mem_k_years;
	keep Admissions_per_1000;
run;

proc summary nway missing data = Members_prior;
	vars RowCnt;
	output out = Number_admissions_prior (drop = _TYPE_ _FREQ_ rename=(RowCnt=num_of_adms)) sum=;
run;

proc summary nway missing data = Members_prior;
	vars MemMos;
	output out = Total_mem_mos_prior (drop = _TYPE_ _FREQ_ rename=(MemMos=Total_memmos)) sum=;
quit;

data Total_mem_k_years_prior;
	set Total_mem_mos_prior;
	Mem_k_years = Total_memmos / 12000;
	keep Mem_k_years;
run;

data Admissions_per_1000_prior;
	merge Number_admissions_prior Total_mem_k_years_prior;
	Admissions_per_1000 = num_of_adms / Mem_k_years;
	keep Admissions_per_1000;
run;


/*Determine if there are readmissions within 30 days (still needs work)*/
data claims_with_readmit;
	set Agg_claims_med;
	by member_id;

	format
		prev_discharge yymmddd10.
		prev_time_period $12.
		Readmit $1.
		;

	if first.member_id then do;
		prev_discharge = date_case_latest;
		prev_time_period = time_slice;
	end;
	if date_case_earliest-prev_discharge le 30
		and date_case_earliest-prev_discharge gt 0
		and prev_time_period = time_slice then do;
		Readmit = 'Y';
		prev_discharge = date_case_latest;
	end;
	else Readmit = 'N';
run;

