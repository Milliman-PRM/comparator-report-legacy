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
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

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

/*Sum the PRM costs (needed for one of the metrics).*/
proc summary nway missing data=All_cases_table;
	vars PRM_Costs;
	class time_slice;
	output out = Total_PRM_Costs (drop = _TYPE_ _FREQ_ rename=(PRM_Costs = PRM_Costs_total)) sum=;
run;

/*Calculate the average risk score and total member months of the institution from the member roster.
  (needed for a couple of the metrics)*/
proc sql;
	create table mems_summary as
	select
		mems.time_period
		,sum(mems.memmos) as total_memmos
		,sum(mems.riskscr_1*memmos) as tot_risk_scr
		,cost.PRM_Costs_total as total_costs
	from post008.members as mems
	left join Total_PRM_Costs as cost
		on mems.time_period = cost.time_slice
	group by time_period, PRM_Costs_total
	;
quit;

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

/*Calculate the requested measures*/
proc sql;
	create table measures as
	select
		detail.name_client
		,detail.time_period
		,"SNF" as metric_category
		,count(distinct detail.prv_id_snf) 
			as distinct_SNFs label="Number of Distinct SNFs utilized in past 12 month period."
		,sum(detail.cnt_discharges_snf)/(mems.total_memmos / 12000)
			as SNF_adm_per_1000_mem_yrs label="SNF Admissions per 1000"
		,(sum(detail.cnt_discharges_snf)/(mems.total_memmos / 12000))/(mems.tot_risk_scr/mems.total_memmos)
			as SNF_adm_per_1000_rsk_adj label="SNF Admissions per 1000, Risk Adjusted"
		,sum(detail.sum_costs_snf)/mems.total_costs
			as perc_cost_total_spend label="% Cost Contribution to Total Spend"
		,sum(detail.sum_days_snf)/sum(detail.cnt_discharges_snf)
			as alos label="SNF ALOS"
		,sum(detail.sum_costs_snf)/sum(detail.sum_days_snf)
			as av_paid_per_day label="Average Paid Per Day in SNF"
		,sum(detail.sum_costs_snf)/sum(detail.cnt_discharges_snf)
			as av_paid_per_disch label="Average Paid Per SNF Discharge"
		,sum(case when detail.los_snf > 21 then cnt_discharges_snf else 0 end)/sum(cnt_discharges_snf)
			as percent_stays_over_21 label="% of SNF stays over 21 days"
	from details_SNF as detail
	left join mems_summary as mems
		on detail.time_period = mems.time_period
	group by detail.time_period, detail.name_client, metric_category, mems.total_memmos, mems.total_costs, mems.tot_risk_scr
	;
quit;

/*Transpose the dataset to get the data into a long format*/
proc transpose data=measures
		out=metrics_transpose(rename=(COL1 = metric_value))
		name=metric_id
		label=metric_name;
	by name_client time_period metric_category;
run;

