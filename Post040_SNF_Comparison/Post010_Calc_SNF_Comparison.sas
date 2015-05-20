/*
### CODE OWNERS: Michael Menser 

### OBJECTIVE:
	Use the PRM outputs to create the Admission / Readmission report for NYP.

### DEVELOPER NOTES:
	This program creates a details table and then individual metrics.
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.PUDD_Methods\*.sas" / source2;

libname post008 "&post008." access = readonly;
libname post040 "&post040.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Create the current and prior data sets summarized at the case level (all cases, not just SNF).*/
%Agg_Claims(
	IncStart=&list_inc_start.
	,IncEnd=&list_inc_end.
	,PaidThru=&list_paid_thru.
	,Time_Slice=&list_time_period.
	,Med_Rx=Med
	,Ongoing_Util_Basis=&post_ongoing_util_basis.
	,Dimensions=providerID~member_ID~prm_line~caseadmitid
	,Force_Util=&post_force_util.
    );

/*Merge the newly created table with the member roster table.  This will be the main table used for calculation of metrics.*/
proc sql noprint;
	create table all_cases_table as
	select 
		A.*
	from agg_claims_med as A 
	inner join post008.members as B 
		on (A.time_slice = B.time_period and A.member_ID = B.member_ID)
	order by time_slice, caseadmitid;
quit;

/*Sum the PRM costs (needed for one of the metrics).*/
proc summary nway missing data=All_cases_table;
	vars PRM_Costs;
	class time_slice;
	output out = Total_PRM_Costs (drop = _:) sum=PRM_Costs_total;
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


proc sql;
	create table snf_windows as
	select
		time_slice
		,member_id
		,caseadmitid
		,min(date_case_earliest) as date_snf_admit format=YYMMDDd10.
		,max(date_case_latest) as date_snf_discharge format=YYMMDDd10.
	from Agg_claims_med
	where lowcase(prm_line) eq "i31"
	group by
		time_slice
		,member_id
		,caseadmitid
	;
quit;

proc sql;
	create table readmit_SNF as
	select distinct
		snf.time_slice
		,snf.member_id
		,snf.caseadmitid
	from snf_windows as snf
	inner join (
		select
			time_slice
			,member_id
			,caseadmitid
			,max(date_case_earliest) as date_acute_admit
		from Agg_claims_med
		where lowcase(prm_line) ne "i31"
		group by
			time_slice
			,member_id
			,caseadmitid
		) as acute on
		snf.time_slice eq acute.time_slice
		and snf.member_id eq acute.member_id
		and (acute.date_acute_admit - snf.date_snf_discharge) between 2 and 30 /*Do not count immediate transfers.*/
	left join snf_windows as snf_interrupts on
		snf.time_slice eq snf_interrupts.time_slice
		and snf.member_id eq snf_interrupts.member_id
		and snf.caseadmitid ne snf_interrupts.caseadmitid
		/*Make sure there wasn't another SNF stay prior to the Acute admit*/
		and snf_interrupts.date_snf_admit between snf.date_snf_discharge and acute.date_acute_admit
	where snf_interrupts.member_id is null
	;
quit;




/*Now limit the cases to SNF cases only.*/
proc sql;
	create table claims_SNF as
	select
		"&name_client." as name_client
		,all_snf.time_slice as time_period
		,all_snf.member_id
		,all_snf.ProviderID as prv_id_snf
		,case
			when readmits.member_id is null then 'N'
			else 'Y'
			end as snf_readmit_yn
		,all_snf.PRM_Util as los_snf
		,all_snf.Discharges as cnt_discharges_snf
		,all_snf.PRM_Util as sum_days_snf
		,all_snf.PRM_Costs as sum_costs_snf
	from All_cases_table as all_snf
	left join readmit_SNF as readmits
		on all_snf.member_id = readmits.member_id
		and all_snf.time_slice = readmits.time_slice
		and all_snf.caseadmitid = readmits.caseadmitid
	where lowcase(prm_line) = "i31"
	;
quit;

/*Aggregate the SNF claims table to the datamart format.*/
proc summary nway missing data=claims_SNF;
	class _character_ los_snf;
	var cnt_discharges_snf sum_days_snf sum_costs_snf;
	output out=details_snf (drop = _:) sum=;
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

		,sum(detail.cnt_discharges_snf)
			/mems.total_memmos * 12000
			as SNF_per1k label="SNF Discharges per 1000"

		,sum(detail.cnt_discharges_snf)
			/mems.tot_risk_scr * 12000
			as SNF_per1k_rskadj label="SNF Admissions per 1000 Risk Adjusted"

		,sum(detail.sum_costs_snf)
			/mems.total_costs
			as pct_SNF_costs label="SNF Costs as a Percentage of Total Costs"

		,sum(detail.sum_days_snf)
			/sum(detail.cnt_discharges_snf)
			as alos label="SNF Average Length of Stay"

		,sum(detail.sum_costs_snf)
			/sum(detail.sum_days_snf)
			as av_paid_per_day label="Average Paid Per Day in SNF"

		,sum(detail.sum_costs_snf)
			/sum(detail.cnt_discharges_snf)
			as av_paid_per_disch label="Average Paid Per SNF Discharge"

		,sum(case when detail.los_snf > 21 then detail.cnt_discharges_snf else 0 end)
			/sum(detail.cnt_discharges_snf)
			as percent_stays_over_21 label="Percentage of SNF stays over 21 days"

		,sum(case when detail.snf_readmit_yn = 'Y' then detail.cnt_discharges_snf else 0 end)
			/sum(detail.cnt_discharges_snf)
			as SNF_readmit label="Percentage of IP Readmits Within 30 Days of SNF Discharge"

	from details_SNF as detail
	left join mems_summary as mems
		on detail.time_period = mems.time_period
	group by 
			detail.time_period
			,detail.name_client
			,mems.total_memmos
			,mems.total_costs
			,mems.tot_risk_scr
	;
quit;

/*Transpose the dataset to get the data into a long format*/
proc transpose data=measures
		out=metrics_transpose(rename=(COL1 = metric_value))
		name=metric_id
		label=metric_name;
	by name_client time_period metric_category;
run;

/*Write the tables out to the post040 library*/
data post040.details_SNF;
	format &details_SNF_cgfrmt.;
	set details_SNF;
	keep &details_SNF_cgflds.;
run;

data post040.metrics_SNF;
	format &metrics_key_value_cgfrmt.;
	set metrics_transpose;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%put return_code = &syscc.;
