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
libname post010 "&post010.";

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

/*Create the current and prior data sets by SNF provider and member.*/
%Agg_Claims(
	IncStart=&inc_start.
	,IncEnd=&inc_end.
	,PaidThru=&paid_thru.
	,Time_Slice=&time_period.
	,Med_Rx=Med
	,Ongoing_Util_Basis=Discharge
	,Dimensions=providerID~member_ID
	,Where_Claims=outclaims_prm.prm_line eq "I31"
    );

/*Merge the newly created table with the member roster table.  This will be the main table used for calculation of metrics.*/
proc sql noprint;
	create table mem_prov_with_risk_scr as
	select A.*, B.riskscr_1
	from members_providers_med as A inner join post008.members as B on (A.time_slice = B.time_period and A.member_ID = B.member_ID);
quit;

proc sort data=mem_prov_with_risk_scr out=mem_prov_with_risk_scr;
	by time_slice member_ID providerID;
run;

/*Calculate the number of distinct SNFs for the current time slice and the prior time slice.*/
proc sql noprint;
	create table Number_NPIs as
	select time_slice, count(distinct ProviderID) as NPI_Count
	from Mem_prov_with_risk_scr
	group by time_slice;
quit;
	
/*Find the number of SNF Admissions per 1000 for the current and prior time slice*/
proc summary nway missing data = Mem_prov_with_risk_scr;
	vars RowCnt MemMos;
	class time_slice;
	output out = Total_adm_memmos (drop = _TYPE_ _FREQ_ rename=(RowCnt=total_num_of_adms MemMos=total_mem_mos)) sum=;
run;

data Admissions_per_thou;
	set Total_adm_memmos;
	adm_per_k_years = total_num_of_adms / (total_mem_mos / 12000);
	keep time_slice adm_per_k_years;
run;

/*Find the risk adjusted SNF Admissions per 1000 for the current and prior periods.*/
data mem_risk_scr_times_memmos;
	set Mem_prov_with_risk_scr;
	risk_scr_times_memmos = MemMos * riskscr_1;
	keep time_slice member_id ProviderID memmos risk_scr_times_memmos;
run;

proc summary nway missing data = mem_risk_scr_times_memmos;
	vars risk_scr_times_memmos memmos;
	class time_slice;
	output out = total_rsk_scr_tms_memmos (drop = _TYPE_ _FREQ_) sum=;
run;

data average_risk_score;
	set total_rsk_scr_tms_memmos;
	average_risk_score = risk_scr_times_memmos / memmos;
	keep time_slice average_risk_score;
run;

data risk_adj_adm_per_1000;
	merge admissions_per_thou average_risk_score;
	risk_adj_adm_per_thou = adm_per_k_years / average_risk_score;
	keep time_slice risk_adj_adm_per_thou;
run; 
	
/*Calculate the % Cost Contribution to Total Spent for the current and prior periods.*/

/*Calculate the SNF ALOS (Average Length of Stay) for the current and prior periods.*/
proc summary nway missing data = Mem_prov_with_risk_scr;
	vars PRM_Util RowCnt;
	class time_slice;
	output out = Total_days_stays (drop = _TYPE_ _FREQ_ rename=(PRM_Util=total_days RowCnt=total_stays)) sum=;
run;

data ALOS;
	set Total_days_stays;
	ALOS = total_days / total_stays;
	keep time_slice ALOS;
run;

/*Calculate Average Paid Per Day in SNF.*/
proc summary nway missing data = Mem_prov_with_risk_scr;
	vars Paid PRM_Util;
	class time_slice;
	output out = Total_paid_days (drop = _TYPE_ _FREQ_ rename=(Paid=total_paid PRM_Util=total_days)) sum=;
run;

data Average_paid_per_day;
	set Total_paid_days;
	Avg_paid_per_day = total_paid / total_days;
	keep time_slice Avg_paid_per_day;
run;

/*Calculate Average Paid Per SNF Discharge.*/
proc summary nway missing data = Mem_prov_with_risk_scr;
	vars Paid Discharges;
	class time_slice;
	output out = Total_paid_discharges (drop = _TYPE_ _FREQ_ rename=(Paid=total_paid Discharges=total_discharges)) sum=;
run;

data Average_paid_per_discharge;
	set Total_paid_discharges;
	Avg_paid_per_disch = total_paid / total_discharges;
	keep time_slice Avg_paid_per_disch;
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

