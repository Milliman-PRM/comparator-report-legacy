/*
### CODE OWNERS: Shea Parkes, Jason Altieri

### OBJECTIVE:
	Calculate various end of life metrics.

### DEVELOPER NOTES:
	Remember the memcnt table is not one record per member.
	Some metrics are per cancer decedent only.
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname post008 "&post008." access=readonly;
libname post010 "&post010." access=readonly;
libname post035 "&post035.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/





proc sql; 
	create table pre_eol_metrics as
	select
		
		"&name_client." as name_client
		,"end_of_life" as metric_category
		,memcnt.time_period as time_period
		,memcnt.elig_status_1 

		,sum(case when memcnt.deceased_yn = "Y" then memcnt.memcnt else 0 end) /
			sum(memcnt.memcnt)
			as mortality_rate label = "Mortality Rate"
			
		,sum(case when memcnt.deceased_yn = "Y" then memcnt.memcnt else 0 end)
			as decedent_count label = "Number of Deaths"

		,calculated mortality_rate / aggs.riskscr_1_avg
			as rsk_adj_mortality_rate label = "Risk Adjusted Mortality Rate"
			
		,calculated decedent_count / aggs.riskscr_1_avg
			as rsk_adj_decedent_count label = "Risk Adjusted Number of Deaths"

		,sum(case when memcnt.deceased_yn = "Y" then memcnt.costs_final_30_days_sum else 0 end) /
			sum(case when memcnt.deceased_yn = "Y" then memcnt.memcnt else 0 end)
			as avg_cost_final_30days label = "Average Cost in 30 Days Prior to Death"
			
		,sum(case when memcnt.deceased_yn = "Y" then memcnt.costs_final_30_days_sum else 0 end)
			as tot_cost_final_30days label = "Total Cost in 30 Days Prior to Death"

		,calculated avg_cost_final_30days / aggs.riskscr_1_avg
			as avg_cost_final_30days_riskadj label = "Average Cost in 30 Days Prior to Death, Risk Adjusted"
			
		,calculated tot_cost_final_30days / aggs.riskscr_1_avg
			as tot_cost_final_30days_riskadj label = "Total Cost in 30 Days Prior to Death, Risk Adjusted"

		,sum(case when memcnt.deceased_hospital_yn = "Y" and memcnt.deceased_yn = "Y" then memcnt.memcnt else 0 end) /
			sum(case when memcnt.deceased_yn = "Y" then memcnt.memcnt else 0 end)
			as pct_death_in_hosp label = "Percentage of Deaths in Hospital"
			
		,sum(case when memcnt.deceased_hospital_yn = "Y" and memcnt.deceased_yn = "Y" then memcnt.memcnt else 0 end)
			as cnt_death_in_hosp label = "Count of Deaths in Hospital"

		,sum(case when memcnt.endoflife_numer_yn_chemolt14days eq "Y" then memcnt.memcnt else 0 end) /
			sum(case when memcnt.endoflife_denom_yn_chemolt14days = "Y" then memcnt.memcnt else 0 end)
			as pct_chemo label = "Percentage of Cancer Decedents Recieving Chemotherapy Within 14 Days of Death"
			
		,sum(case when memcnt.endoflife_numer_yn_chemolt14days eq "Y" then memcnt.memcnt else 0 end)
			as cnt_chemo label = "Count of Cancer Decedents Recieving Chemotherapy Within 14 Days of Death"

		,sum(case when memcnt.endoflife_numer_yn_hospicelt3day eq "Y" then memcnt.memcnt else 0 end) /
			sum(case when memcnt.endoflife_denom_yn_hospicelt3day = "Y" then memcnt.memcnt else 0 end)
			as pct_cancer_hospice_lt3days label = "Percentage of Cancer Decedents Admitted to Hospice for Less Than 3 Days"

		,sum(case when memcnt.endoflife_numer_yn_hospicelt3day eq "Y" then memcnt.memcnt else 0 end)
			as cnt_cancer_hospice_lt3days label = "Count of Cancer Decedents Admitted to Hospice for Less Than 3 Days"
			
		,sum(case when memcnt.endoflife_numer_yn_hospicenever eq "Y" then memcnt.memcnt else 0 end) /
			sum(case when memcnt.endoflife_denom_yn_hospicenever = "Y" then memcnt.memcnt else 0 end)
			as pct_cancer_hospice_never label = "Percentage of Cancer Decedents Never Admitted to Hospice"
			
		,sum(case when memcnt.endoflife_numer_yn_hospicenever eq "Y" then memcnt.memcnt else 0 end)
			as cnt_cancer_hospice_never label = "Count of Cancer Decedents Never Admitted to Hospice"

		,sum(case when memcnt.final_hospice_days lt 3 and memcnt.final_hospice_days gt 0 then memcnt.memcnt else 0 end) /
			sum(case when memcnt.final_hospice_days gt 0 then memcnt.memcnt else 0 end)
			as pct_hospice_lt3days label = "Percentage of Hospice Decedents Admitted to Hospice for Less Than 3 Days"
			
		,sum(case when memcnt.final_hospice_days lt 3 and memcnt.final_hospice_days gt 0 then memcnt.memcnt else 0 end)
			as cnt_hospice_lt3days label = "Count of Hospice Decedents Admitted to Hospice for Less Than 3 Days"

		,sum(case when memcnt.final_hospice_days eq 0 and memcnt.deceased_yn = "Y" then memcnt.memcnt else 0 end) /
			sum(case when memcnt.deceased_yn = "Y" then memcnt.memcnt else 0 end)
			as pct_hospice_never label = "Percentage of Decedents Never Admitted to Hospice"
			
		,sum(case when memcnt.final_hospice_days eq 0 and memcnt.deceased_yn = "Y" then memcnt.memcnt else 0 end)
			as cnt_hospice_never label = "Count of Decedents Never Admitted to Hospice"

		,sum(case when final_hospice_days gt 365.25/2 then memcnt.memcnt else 0 end) /
			sum(case when memcnt.deceased_yn = "Y" then memcnt.memcnt else 0 end)
			as pct_hospice_gt_6months label = "Percentage of Decedents in Hospice Over 6 Months"
			
		,sum(case when final_hospice_days gt 365.25/2 then memcnt.memcnt else 0 end)
			as cnt_hospice_gt_6months label = "Count of Decedents in Hospice Over 6 Months"

	from post008.memcnt as memcnt
	left join post010.basic_aggs_elig_status as aggs
			on memcnt.time_period = aggs.time_period
			and memcnt.elig_status_1 = aggs.elig_status_1
	group by 
			memcnt.time_period
			,memcnt.elig_status_1
			,aggs.riskscr_1_avg
	;
quit;


/*Munge to target formats*/
proc transpose data=pre_eol_metrics 
				out=EOL_transpose(rename=(COL1 = metric_value))
				name=metric_id
				label=metric_name;
	by name_client time_period metric_category elig_status_1;
run;

data post035.metrics_endoflife;
	format &metrics_key_value_cgfrmt.;
	set EOL_transpose;
	where metric_value ne .; /*Some time periods will not have any qualifying decedents.*/
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%LabelDataSet(post035.metrics_endoflife);

%put return_code = &syscc.;
