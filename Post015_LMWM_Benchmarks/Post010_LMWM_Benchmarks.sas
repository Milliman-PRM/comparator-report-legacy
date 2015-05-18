/*
### CODE OWNERS: Aaron Hoch, Kyle Baird

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
libname post010 "&post010." access=readonly;
libname post015 "&post015.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


/*Perform the risk-adjustment on the loosely-managed benchmarks
  across all combinations of time period and beneficiary status.*/
proc sql noprint;
	create table Risk_adj_loose_man_bench as
		select scores.time_period
				,loose.mcrm_line
				,scores.elig_status_1

				/*Calculate risk-adjusted benchmarks*/
				,case
					when loose.admits_per_1000 is not null then loose.admits_per_1000 * scores.riskscr_1_avg
					else 0
					end
					as benchmark_discharges_per1k
				,case
					when upcase(loose.annual_util_type) = "DAYS" then loose.annual_util_per_1000 * scores.riskscr_1_avg
					else 0
					end
					as benchmark_days_per1k
				,coalesce(loose.annual_util_per_1000,0) * scores.riskscr_1_avg as benchmark_util_per1k
	from post010.basic_aggregation_elig_status as scores
	cross join 
		M015_out.benchmarks_loosely_managed as loose
	order by
		scores.time_period
		,loose.mcrm_line
		,scores.elig_status_1
	;
quit;


/*Cross-join the well-managed benchmarks so that we duplicate them
  across all combinations of time period and beneficiary status*/
proc sql noprint;
	create table cart_prod_well_man_benchmarks as
		select groups.time_period
				,well.mcrm_line
				,groups.elig_status_1
				,coalesce(well.admits_per_1000,0) as benchmark_discharges_per1k
				,case
					when upcase(well.annual_util_type) = "DAYS" then well.annual_util_per_1000
					else 0
					end
					as benchmark_days_per1k
				,coalesce(well.annual_util_per_1000,0) as benchmark_util_per1k
	from post010.basic_aggregation_elig_status as groups
	cross join
		M015_Out.benchmarks_well_managed as well
	order by
		groups.time_period
		,well.mcrm_line
		,groups.elig_status_1
	;
quit;


/*Stack the loosley-managed and the well-managed benchmarks*/
data Post015.cost_util_benchmark (keep=&cost_util_benchmark_cgflds.);

	format &cost_util_benchmark_cgfrmt.;

	set Risk_adj_loose_man_bench (in= loose)
		cart_prod_well_man_benchmarks (in= well);
	by
		time_period
		mcrm_line
		elig_status_1
		;
	
	&assign_name_client.;
	
	if loose then type_benchmark = "Loose";
		else if well then type_benchmark = "Well";
	
run;

%LabelDataset(Post015.cost_util_benchmark);


%put System Return Code = &syscc.;

