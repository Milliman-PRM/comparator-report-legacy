/*
### CODE OWNERS: Michael Menser, Shea Parkes, Jason Altieri

### OBJECTIVE:
	Create the memcnt table from the member roster.

### DEVELOPER NOTES:
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname M180_Out "&M180_Out." access=readonly;
libname post010 "&post010." access=readonly;
libname post008 "&post008." access=readonly;
libname post025 "&post025." access=readonly;
libname post035 "&post035.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

proc sql; 
	create table pre_eol_metrics as
	select
		
		"&name_client." as name_client
		,"End Of Life" as metric_category
		,memcnt.time_period as time_period

		,sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end) /
			sum(memcnt.memcnt)
			as mortality_rate label = "Mortality Rate"

		,(sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end) /
			sum(memcnt.memcnt) ) / aggs.riskscr_1_avg
			as rsk_adj_mortality_rate label = "Risk Adjusted Mortality Rate"

		,(sum(case when memcnt.deceased_yn = "Y" then memcnt.costs_final_30_days else 0 end) /
			sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end)) / aggs.riskscr_1_avg
			as avg_cost_final_30days label = "Average Cost in 30 Days Prior to Death, Risk Adjusted"

		,sum(case when deceased_hospital_yn = "Y" then 1 else 0 end) /
			sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end)
			as pct_death_in_hosp label = "Percentage of Deaths in Hospital"

		,sum(case when deceased_chemo_yn eq "Y" then 1 else 0 end) /
			sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end)
			as pct_chemo label = "Percentage of Decedents Recieving Chemotherapy Within 14 Days of Death"

		,sum(case when memcnt.hospice_lt_3days eq "Y" then 1 else 0 end)/
			sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end)
			as pct_hospice_lt3days label = "Percentage of Decedents Admitted to Hospice for Less Than 3 Days"

		,sum(case when memcnt.hospice_never eq "Y" then 1 else 0 end)/
			sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end)
			as pct_hospice_never label = "Percentage of Decedents Never Admitted to Hospice"

		,sum(case when final_hospice_days gt 180 then 1 else 0 end) /
			sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end)
			as pct_hospice_gt_6months label = "Percentage of Decedents in Hospice Over 6 Months"

	from post008.memcnt as memcnt
	left join post010.basic_aggs as aggs
			on memcnt.time_period = aggs.time_period
	group by 
			memcnt.time_period
			,aggs.riskscr_1_avg
	;
quit;


/*Munge to target formats*/
proc transpose data=pre_eol_metrics 
				out=EOL_transpose(rename=(COL1 = metric_value))
				name=metric_id
				label=metric_name;
	by name_client time_period metric_category;
run;

data post035.metrics_endoflife;
	format &metrics_key_value_cgfrmt.;
	set EOL_transpose;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%LabelDataSet(post035.metrics_endoflife);

%put return_code = &syscc.;
