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
	create table details_summary_snf as
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
	create table cost_util_summary_snf as
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
	create table comparison_snf as
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
	from details_summary_snf as snf
	full join
	cost_util_summary_snf as cost
	on	snf.name_client = cost.name_client and
		snf.time_period = cost.time_period and
		snf.elig_status_1 = cost.elig_status_1 	
	;
quit;

data differences_snf;
	set comparison_snf;
	where (total_disch_snf_table ne total_disch_util_table) or 
		  (total_days_snf_table ne total_days_util_table) or
		  (total_costs_snf_table ne total_costs_util_table);
run;

%AssertDataSetNotPopulated(differences_snf,ReturnMessage=There are discreptancies between the SNF table and Util table.)

/*Create macro to compare inpatient table and cost_util table at different aggregation levels.*/

%macro Check_Details_Inp(details_inp_label, details_inp_field, details_inp_value)
	/*Roll up the inpatient table in order to compare it to the cost_util table.*/
	proc sql;
		create table details_inp_summary_&details_inp_label as
		select
			name_client
			,time_period
			,elig_status_1
			,sum(cnt_discharges_inpatient) as total_disch_inpatient_table
			,sum(sum_days_inpatient) as total_days_inpatient_table
			,sum(sum_costs_inpatient) as total_costs_inpatient_table
		from Post050.details_inpatient
		where &details_inp_field = &details_inp_value
		group by
			name_client
			,time_period
			,elig_status_1
		;
	quit;

	/*Roll up the cost util table.*/
	proc sql;
		create table cost_util_summary_&details_inp_label as
		select
			name_client
			,time_period
			,elig_status_1
			,sum(prm_discharges) as total_disch_util_table
			,sum(prm_days) as total_days_util_table
			,sum(prm_costs) as total_costs_util_table
		from Post050.cost_util
		where &details_inp_field = &details_inp_value
		group by
			name_client
			,time_period
			,elig_status_1
		;
	quit;

	/*Validate that the two tables match*/
	proc sql;
		create table comparison_&details_inp_label as
		select 
			inp.name_client
			,inp.time_period
			,inp.elig_status_1
			,round(inp.total_disch_inpatient_table,1) as total_disch_inpatient_table /*Round to prevent floating point issues.*/
			,round(inp.total_days_inpatient_table,1) as total_days_inpatient_table
			,round(inp.total_costs_inpatient_table,.01) as total_costs_inpatient_table
			,round(cost.total_disch_util_table,1) as total_disch_util_table
			,round(cost.total_days_util_table,1) as total_days_util_table
			,round(cost.total_costs_util_table,.01) as total_costs_util_table
		from details_inp_summary_&details_inp_label as inp
		full join
		cost_util_summary_&details_inp_label as cost
		on	inp.name_client = cost.name_client and
			inp.time_period = cost.time_period and
			inp.elig_status_1 = cost.elig_status_1 	
		;
	quit;

	data differences_&details_inp_label;
		set comparison_&details_inp_label;
		where (total_disch_inpatient_table ne total_disch_util_table) or 
		  	(total_days_inpatient_table ne total_days_util_table) or
		  	(total_costs_inpatient_table ne total_costs_util_table);
	run;

	%AssertDataSetNotPopulated(differences_&details_inp_label, ReturnMessage=There are discreptancies between the inpatient table and Util table
	at the &details_inp_label level.);

%mend

%put System Return Code = &syscc.;
