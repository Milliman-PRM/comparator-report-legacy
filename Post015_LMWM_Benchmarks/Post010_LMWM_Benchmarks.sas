/*
### CODE OWNERS: Aaron Hoch, Kyle Baird, Jason Altieri

### OBJECTIVE:
	Internalize the logic for generating Loosely and Well-Managed Benchmarks.

### DEVELOPER NOTES:
	<none>
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

/* Libnames */
libname M015_Out "&M015_Out." access=readonly;
libname post008 "&post008." access=readonly;
libname post009 "&post009." access=readonly;
libname post015 "&post015.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


/*Perform the risk-adjustment on the loosely-managed benchmarks.
  Create a table with LM/WM benchmarks across all combinations of 
  time period and beneficiary status.*/
proc sql noprint;
	create table Risk_adj_man_bench as
	select 
		member_dims.time_period
		,bench.loosely_well as type_benchmark
		,ref_mcrm_line.mcrm_line
		,member_dims.elig_status_1
		/*** vvv COLUMNS HELPFUL FOR DEVELOPMENT/DIAGNOSTICS vvv ***/
		,case
			when upcase(bench.loosely_well) eq "LOOSELY" then riskscr.riskscr_1_util_avg
			else 1.0 /*No risk adjustment done to well managed benchmarks*/
			end
			as risk_adjustment_util
		,case
			when upcase(bench.loosely_well) eq "LOOSELY" then riskscr.riskscr_1_cost_avg
			else 1.0 /*No risk adjustment done to well managed benchmarks*/
			end
			as risk_adjustment_cost
		,bench.admits_per1k
		,bench.util_per1k
		/*** ^^^ COLUMNS HELPFUL FOR DEVELOPMENT/DIAGNOSTICS ^^^ ***/
		,case
			when bench.admits_per1k is not null then bench.admits_per1k * calculated risk_adjustment_util
			else 0
			end
			as benchmark_discharges_per1k
		,case
			when upcase(bench.util_type) eq "DAYS" then bench.util_per1k * calculated risk_adjustment_util
			else 0
			end
			as benchmark_days_per1k
		,coalesce(bench.util_per1k,0) * calculated risk_adjustment_util as benchmark_util_per1k
	from (
		select distinct
			time_period
			,elig_status_1
		from post008.members
		) as member_dims
	cross join M015_out.ref_mcrm_line (where = (upcase(lob) eq "%upcase(&type_benchmark_hcg.)")) as ref_mcrm_line
	inner join M015_out.benchmarks_hcg as bench on
		ref_mcrm_line.lob eq bench.lob
		and ref_mcrm_line.mcrm_line eq bench.mcrm_line
	left join post009.riskscr_service as riskscr on
		member_dims.time_period eq riskscr.time_period
			and member_dims.elig_status_1 eq riskscr.elig_status_1
			and ref_mcrm_line.mcrm_line eq riskscr.mcrm_line
	order by
		member_dims.time_period
		,type_benchmark
		,ref_mcrm_line.mcrm_line
		,member_dims.elig_status_1
	;
quit;

/*Format the benchmarks for output to the network*/
data Post015.cost_util_benchmark (keep=&cost_util_benchmark_cgflds.);
	format &cost_util_benchmark_cgfrmt.;
	set Risk_adj_man_bench;
	&assign_name_client.;
run;
%LabelDataset(Post015.cost_util_benchmark);

%put System Return Code = &syscc.;
