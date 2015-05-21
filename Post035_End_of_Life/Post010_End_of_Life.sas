/*
### CODE OWNERS: Jason Altier

### OBJECTIVE:
	Use the PRM outputs to calculate the end of life metrics for NYP.

### DEVELOPER NOTES:
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;
%include "&M073_Cde.pudd_methods\*.sas";

/*Libnames*/
libname M155_Out "&M155_Out." access=readonly;
libname post008 "&post008." access=readonly;
libname post010 "&post010." access=readonly;
libname post025 "&post035.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

proc sql;
	create table decedents_w_decorators as
	select 
		decor.*
		,decdents_w_time.time_period
	from M155_Out.Endoflife_decor as decor
	inner join post008.members as mems
		on decor.member_id = mems.member_id
	inner join (
		select
		decedents.member_id
		,time.time_period
		from M155_Out.decedents as decedents
		inner join post008.time_windows as time
			on decedents.death_date between time.inc_start and time.inc_end
			) as decdents_w_time
	on decor.member_id = decdents_w_time.member_id and mems.time_period = decdents_w_time.time_period
	;
quit;


proc sql; 
	create table metrics_end_of_life as
	select
		
		"&name_client." as name_client
		,decedents.time_period as time_period

		,count (distinct decedents.member_id) /
			sum(memcnt.memcnt)
			as mortality_rate label = "Mortality Rate"

		,(count (distinct decedents.member_id) /
			sum(memcnt.memcnt) ) / aggs.riskscr_1_avg
			as rsk_adj_mortality_rate label = "Risk Adjusted Mortality Rate"

		/*PUT IN AVG COST 30 DAYS PRIOR TO DEATH*/

		/*% of deaths in hospital*/

		,sum(case when decedents.endoflife_numer_yn_chemolt14days eq "Y" then 1 else 0 end) /
			sum(case when decedents.endoflife_denom_yn_chemolt14days eq "Y" then 1 else 0 end)
			as pct_chemo label = "Percentage of Decedents Recieving Chemotherapy Within 14 Days of Death"

		,sum(case when decedents.endoflife_numer_yn_hospicelt3day eq "Y" then 1 else 0 end)/
			sum(case when decedents.endoflife_denom_yn_hospicelt3day eq "Y" then 1 else 0 end)
			as pct_hospice_lt3days label = "Percent of Decedents Admitted to Hospice for Less Than 3 Days"

		,sum(case when decedents.endoflife_numer_yn_hospicenever eq "Y" then 1 else 0 end)/
			sum(case when decedents.endoflife_denom_yn_hospicenever eq "Y" then 1 else 0 end)
			as pct_hospice_never label = "Percent of Decedents Never Admitted to Hospice"

		/*% of decedents admitted to hospice greater than 6 months*/

	from decedents_w_decorators as decedents
	left join post010.basic_aggs as aggs
			on decedents.time_period = aggs.time_period
	left join post008.memcnt as memcnt
			on decedents.time_period = memcnt.time_period
	group by 
			decedents.time_period
			,aggs.riskscr_1_avg
	;
quit;

















/*Calculate the requested measures*/

data post035.;
	format &details_inpatient_cgfrmt.;
	set details_inpatient;
	keep &details_inpatient_cgflds.;
run;

data post035.;
	format &metrics_key_value_cgfrmt.;
	set metrics_transpose;
	keep &metrics_key_value_cgflds.;
	attrib _all_ label = ' ';
run;

%put return_code = &syscc.;
