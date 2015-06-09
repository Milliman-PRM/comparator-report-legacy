/*
### CODE OWNERS: Michael Menser

### OBJECTIVE:
	Validate that the two details tables (SNF and inpatient) and the cost_util table match up as expected.

### DEVELOPER NOTES:
	<none>
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname post050 "&post050." access = readonly;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Roll up the SNF table in order to compare it to the cost_util table.*/
proc sql;
	create table details_snf_summary as
	select
		name_client
		,time_period
		,elig_status_1
		,sum(cnt_discharges_snf) as total_disch_snf_table
		,sum(sum_days_snf) as total_days_snf_table
		,sum(sum_costs_snf) as total_costs_snf_table
	from Post050.details_SNF
	group by
		name_client
		,time_period
		,elig_status_1
	;
quit;
		
/*Now roll up the cost_util table.*/
proc sql;
	create table cost_util_summary as
	select
		name_client
		,time_period
		,elig_status_1
		,sum(prm_discharges) as total_disch_util_table
		,sum(prm_days) as total_days_util_table
		,sum(prm_costs) as total_costs_util_table
	from Post050.cost_util
	where UPCASE(prm_line) = 'I31'
	group by
		name_client
		,time_period
		,elig_status_1
	;
quit;

/*Validate that the two tables match*/
proc sql;
	create table comparison as
	select 
		snf.name_client
		,snf.time_period
		,snf.elig_status_1
		,round(snf.total_disch_snf_table,1) as total_disch_snf_table /*Round to prevent floating point issues.*/
		,round(snf.total_days_snf_table,1) as total_days_snf_table
		,round(snf.total_costs_snf_table,.01) as total_costs_snf_table
		,round(cost.total_disch_util_table,1) as total_disch_util_table
		,round(cost.total_days_util_table,1) as total_days_util_table
		,round(cost.total_costs_util_table,.01) as total_costs_util_table
	from details_snf_summary as snf
	full join
	cost_util_summary as cost
	on	snf.name_client = cost.name_client and
		snf.time_period = cost.time_period and
		snf.elig_status_1 = cost.elig_status_1 	
	;
quit;

data differences;
	set comparison;
	where (total_disch_snf_table ne total_disch_util_table) or 
		  (total_days_snf_table ne total_days_util_table) or
		  (total_costs_snf_table ne total_costs_util_table);
run;

%AssertDataSetNotPopulated(differences,ReturnMessage=There are discreptancies between the SNF table and Util table.)

%put System Return Code = &syscc.;
