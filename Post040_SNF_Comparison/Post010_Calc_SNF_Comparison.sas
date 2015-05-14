/*
### CODE OWNERS: Michael Menser 

### OBJECTIVE:
	Use the PRM outputs to create the Admission / Readmission report for NYP.

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

/*Create the current and prior data sets summarized at the case level (all cases, not just SNF).*/
%Agg_Claims(
	IncStart=&inc_start.
	,IncEnd=&inc_end.
	,PaidThru=&paid_thru.
	,Time_Slice=&time_period.
	,Med_Rx=Med
	,Ongoing_Util_Basis=Discharge
	,Dimensions=providerID~member_ID~prm_line~caseadmitid
    );

/*Merge the newly created table with the member roster table.  This will be the main table used for calculation of metrics.*/
proc sql noprint;
	create table all_cases_table as
	select A.*
	from agg_claims_med as A inner join post008.members as B on (A.time_slice = B.time_period and A.member_ID = B.member_ID)
	order by time_slice, caseadmitid;
quit;

/*Calculate the average risk score and total member months of the institution from the member roster.
  (needed for a couple of the metrics)*/
data mem_risk_scr_times_memmos;
	set Post008.Members;
	risk_scr_times_memmos = memmos * riskscr_1;
	keep time_period member_id memmos riskscr_1 risk_scr_times_memmos;
run;

proc summary nway missing data = Mem_risk_scr_times_memmos;
	vars memmos risk_scr_times_memmos;
	class time_period;
	output out = Total_memmos_total_riskscr (drop = _TYPE_ _FREQ_ rename=(memmos=memmos_total risk_scr_times_memmos=risk_scr_total)) sum=;
run;

data Total_memmos_av_riskscr;
	set Total_memmos_total_riskscr;
	average_risk_score = risk_scr_total / memmos_total;
	keep time_period memmos_total average_risk_score;
run;

/*Sum the PRM costs (needed for one of the metrics).*/
proc summary nway missing data=All_cases_table;
	vars PRM_Costs;
	class time_slice;
	output out = Total_PRM_Costs (drop = _TYPE_ _FREQ_ rename=(PRM_Costs = PRM_Costs_total)) sum=;
run;

/*Now limit the cases to SNF cases only.*/
proc sql;
	create table claims_SNF as
	select
		"&name_client." as name_client
		,time_slice as time_period
		,member_id
		,ProviderID as prv_id_snf
		,'N' as snf_readmit_yn
		,PRM_Util as los_snf
		,Discharges as cnt_discharges_snf
		,PRM_Util as sum_days_snf
		,PRM_Costs as sum_costs_snf
	from All_cases_table
	where prm_line = "I31"
	;
quit;

/*Aggregate the SNF claims table to the datamart format.*/
proc summary nway missing data=claims_SNF;
	class name_client time_period prv_id_snf snf_readmit_yn los_snf;
	var cnt_discharges_snf sum_days_snf sum_costs_snf;
	output out=details_snf (drop = _TYPE_ _FREQ_) sum=;
run;

/*Calculate the number of distinct SNFs for all time slices.*/
proc sql noprint;
	create table Number_NPIs as
	select time_slice, count(distinct ProviderID) as NPI_Count
	from SNF_cases_table
	group by time_slice;
quit;

/*Find the number of SNF Admissions per 1000 for all time periods (including risk adjusted)*/
proc summary nway missing data = SNF_cases_table;
	vars RowCnt;
	class time_slice;
	output out = Total_SNF_admin (drop = _TYPE_ _FREQ_ rename=(RowCnt=total_num_of_adms )) sum=;
run;

data SNF_Admissions_per_thou;
	merge Total_snf_admin Total_memmos_av_riskscr;
	Adm_per_mem_k_years = (total_num_of_adms / memmos_total) * 12000;
	Adm_per_mem_k_years_rsk_adj = Adm_per_mem_k_years / average_risk_score;
	keep time_slice adm_per_mem_k_years Adm_per_mem_k_years_rsk_adj;
run;

/*Calculate % Cost Contribution to Total Spend*/
proc summary nway missing data = SNF_cases_table;
	vars PRM_Costs;
	class time_slice;
	output out = Total_SNF_costs (drop = _TYPE_ _FREQ_ rename=(PRM_Costs = Total_SNF_costs)) sum=;
run;

data perc_contr_total_spend;
	merge total_snf_costs total_prm_costs;
	perc_SNF_total_spend = Total_SNF_costs / PRM_Costs_total;
	keep time_slice perc_SNF_total_spend;
run; 

/*Calculate the SNF ALOS (Average Length of Stay) for all time periods.*/
proc summary nway missing data = SNF_cases_table;
	vars PRM_Util Discharges;
	class time_slice;
	where Discharges = 1;
	output out = Total_days_stays (drop = _TYPE_ _FREQ_ rename=(PRM_Util=total_days Discharges=total_stays)) sum=;
run;

data ALOS;
	set Total_days_stays;
	ALOS = total_days / total_stays;
	keep time_slice ALOS;
run;

/*Calculate Average Paid Per Day in SNF.*/
proc summary nway missing data = SNF_cases_table;
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
proc summary nway missing data = SNF_cases_table;
	vars Paid Discharges;
	class time_slice;
	where Discharges = 1;
	output out = Total_paid_discharges (drop = _TYPE_ _FREQ_ rename=(Paid=total_paid Discharges=total_discharges)) sum=;
run;

data Average_paid_per_discharge;
	set Total_paid_discharges;
	Avg_paid_per_disch = total_paid / total_discharges;
	keep time_slice Avg_paid_per_disch;
run;

/*Calculate % of SNF stays over 21 days*/
proc summary nway missing data = SNF_cases_table;
	vars Discharges;
	class time_slice;
	where Discharges = 1 and PRM_Util gt 21;
	output out = Num_disch_over_21_days (drop = _TYPE_ _FREQ_ rename=(Discharges=total_discharges_over_21)) sum=;
run;

data percent_disch_over_21_days;
	merge Num_disch_over_21_days Total_paid_discharges;
	percent_over_21 = total_discharges_over_21 / total_discharges;
	keep time_slice percent_over_21;
run;
	
/*In order to calculate % Cost Contribution to Total Spend, we need a table with all data, not limited to SNF data.  Generate this now.*/
%Agg_Claims(
	IncStart=&inc_start.
	,IncEnd=&inc_end.
	,PaidThru=&paid_thru.
	,Time_Slice=&time_period.
	,Med_Rx=Med
	,Ongoing_Util_Basis=Discharge
	,Dimensions=providerID~member_ID~prm_line~caseadmitid
	,Where_Claims=outclaims_prm.prm_line eq "I31"
	,Suffix_Output=all
    );



/*Merge the newly created table with the member roster table.*/

/*Calculate percent of SNF stays over 21 days*/


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

