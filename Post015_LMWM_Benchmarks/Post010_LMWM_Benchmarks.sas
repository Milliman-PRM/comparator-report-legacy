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
libname post010 "&post010." access=readonly;
libname post015 "&post015.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


/*Perform the risk-adjustment on the loosely-managed benchmarks.
  Create a table with LM/WM benchmarks across all combinations of 
  time period and beneficiary status.*/
proc sql noprint;
	create table Risk_adj_man_bench as
		select scores.time_period
				,bench.benchmark_type as type_benchmark format=$8. length=8 /*To match datamart definition*/
				,bench.mcrm_line
				,scores.elig_status_1

				/*Risk adjust the loosely managed benchmarks and use the raw well managed benchmarks*/
				,case
					when bench.admits_per_1000 is not null then 
						case when upcase(bench.benchmark_type) = "LOOSELY" then
							bench.admits_per_1000 * scores.riskscr_1_avg
							else bench.admits_per_1000 end
					else 0
					end
					as benchmark_discharges_per1k
				,case
					when upcase(bench.annual_util_type) = "DAYS" then 
						case when upcase(bench.benchmark_type) = "LOOSELY" then
							bench.annual_util_per_1000 * scores.riskscr_1_avg
							else bench.annual_util_per_1000 end
					else 0
					end
					as benchmark_days_per1k
				,case when upcase(bench.benchmark_type) = "LOOSELY" then
					coalesce(bench.annual_util_per_1000,0) * scores.riskscr_1_avg 
					else coalesce(bench.annual_util_per_1000,0) 
					end
					as benchmark_util_per1k
	from post010.basic_aggs_elig_status as scores
	cross join 
		M015_out.hcg_benchmarks_nationwide as bench
	where upcase(bench.lob) = "upcase(&type_benchmark_hcg.)"
	order by
		scores.time_period
		,type_benchmark
		,bench.mcrm_line
		,scores.elig_status_1
	;
quit;


/*Format the benchmarks for output to the network*/
data Post015.cost_util_benchmark (keep=&cost_util_benchmark_cgflds.);

	format &cost_util_benchmark_cgfrmt.;

	set Risk_adj_man_bench;
	by
		time_period
		type_benchmark
		mcrm_line
		elig_status_1
		;
	
	&assign_name_client.;
run;

%LabelDataset(Post015.cost_util_benchmark);


%put System Return Code = &syscc.;

