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

libname M180_Out "&M180_Out.";
libname post008 "&post008.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Find the number of members for each combination of key variables (the memcnt table)*/
proc sql;
	create table memcnt_to_export as
	select
		"&name_client." as name_client
		,mems.time_period
		,mems.elig_status_1
		,case when decedents_w_time.member_id_excluded is not null then 'Y' else 'N' end as deceased_yn /*TODO: Append with Decedent/End of Life information when available*/ 
		,'N' as deceased_hospital_yn
		,coalesce(decedents_w_time.endoflife_numer_yn_chemolt14days, 'N') as deceased_chemo_yn
		,coalesce(decedents_w_time.endoflife_numer_yn_hospicelt3day, 'N') as hospice_lt_3days
		,coalesce(decedents_w_time.endoflife_numer_yn_hospicenever,'N') as hospice_never
		,0 as final_hospice_days
		,count(*) as memcnt
	from post008.Members as mems
	left join (
			select
				decedents.member_id_excluded
				,decedents.endoflife_numer_yn_chemolt14days
				,decedents.endoflife_numer_yn_hospicenever
				,decedents.endoflife_numer_yn_hospicelt3day
				,time.time_period
			from M180_Out.Puad12_member_excluded as decedents
			inner join post008.time_windows as time
				on decedents.death_date_excluded between time.inc_start and time.inc_end
			where upcase(decedents.report_status_excluded) = "DEATH"
				) as decedents_w_time
		on mems.member_id = decedents_w_time.member_id_excluded 
		and mems.time_period = decedents_w_time.time_period
	group by mems.time_period
			,mems.elig_status_1
			,decedents_w_time.time_period
			,deceased_yn
			,deceased_hospital_yn
			,deceased_chemo_yn
			,hospice_lt_3days
			,hospice_never
			,final_hospice_days
			,decedents_w_time.member_id_excluded
			,decedents_w_time.endoflife_numer_yn_chemolt14days
			,decedents_w_time.endoflife_numer_yn_hospicelt3day
			,decedents_w_time.endoflife_numer_yn_hospicenever
	;
quit;


proc sql; 
	create table pre_eol_metrics as
	select
		
		"&name_client." as name_client
		,memcnt.time_period as time_period

		,sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end) /
			sum(memcnt.memcnt)
			as mortality_rate label = "Mortality Rate"

		,(sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end) /
			sum(memcnt.memcnt) ) / aggs.riskscr_1_avg
			as rsk_adj_mortality_rate label = "Risk Adjusted Mortality Rate"

		/*PUT IN AVG COST 30 DAYS PRIOR TO DEATH*/

		/*% of deaths in hospital*/

		,sum(case when deceased_chemo_yn eq "Y" then 1 else 0 end) /
			sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end)
			as pct_chemo label = "Percentage of Decedents Recieving Chemotherapy Within 14 Days of Death"

		,sum(case when memcnt.hospice_lt_3days eq "Y" then 1 else 0 end)/
			sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end)
			as pct_hospice_lt3days label = "Percent of Decedents Admitted to Hospice for Less Than 3 Days"

		,sum(case when memcnt.hospice_never eq "Y" then 1 else 0 end)/
			sum(case when memcnt.deceased_yn = "Y" then 1 else 0 end)
			as pct_hospice_never label = "Percent of Decedents Never Admitted to Hospice"

		/*% of decedents admitted to hospice greater than 6 months*/

	from memcnt_to_export as memcnt
	left join post010.basic_aggs as aggs
			on memcnt.time_period = aggs.time_period
	group by 
			memcnt.time_period
			,aggs.riskscr_1_avg
	;
quit;






data post008.memcnt;
	format &memcnt_cgfrmt.;
	set memcnt_to_export;
	keep &memcnt_cgflds.;
run;

%LabelDataSet(post008.memcnt);

%put return_code = &syscc.;
