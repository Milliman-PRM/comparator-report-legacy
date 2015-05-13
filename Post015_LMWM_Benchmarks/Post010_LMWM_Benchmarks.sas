/*
### CODE OWNERS: Aaron Hoch

### OBJECTIVE:
	Internalize the logic for generating Loosely and Well-Managed Benchmarks.

### DEVELOPER NOTES:

*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";
%include "&M073_Cde.pudd_methods\*.sas";

/* Libnames */
libname M015_Out "&M015_Out." access=readonly;
libname post008 "&post008." access=readonly;
libname post010 "&post010." access=readonly;
libname post015 "&post015.";

%let assign_name_client = name_client = "&name_client.";
%put assign_name_client = &assign_name_client.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Compute the average risk score across all combinations of 
  beneficiary status and time period*/
proc means missing nway noprint data=Post008.members;
	class time_period elig_status_1;
	var riskscr_1;
	output out= grouped_avg_risk_scrores (drop= _:) mean(riskscr_1) = Avg_Risk_Score;
run;

/*Perform the risk-adjustment on the loosely-managed benchmarks
  across all combinations of time period and beneficiary status.*/
proc sql noprint;
	create table Risk_adj_loose_man_bench as
		select scores.time_period
				,loose.mcrm_line
				,scores.elig_status_1

				/*Calculate risk-adjusted benchmarks*/
				,(loose.admits_per_1000 * scores.Avg_Risk_Score) 
					as benchmark_discharges_per1k

				,case when upcase(loose.annual_util_type) = "DAYS" 
					then
						(loose.annual_util_per_1000 * scores.Avg_Risk_Score) 
					else 0
					end
					as benchmark_days_per1k

				,(loose.annual_util_per_1000 * scores.Avg_Risk_Score) 
					as benchmark_util_per1k

	from grouped_avg_risk_scrores as scores
	cross join 
		M015_out.loosely_managed_benchmarks as loose	
	;
quit;


/*Cross-join the well-managed benchmarks so that we duplicate them
  across all combinations of time period and beneficiary status*/
proc sql noprint;
	create table cart_prod_well_man_benchmarks as
		select groups.time_period
				,well.mcrm_line
				,groups.elig_status_1
				,well.admits_per_1000 as benchmark_discharges_per1k
				
				,case when upcase(well.annual_util_type) = "DAYS" 
					then
						well.annual_util_per_1000 
					else 0
					end
					as benchmark_days_per1k

				,well.annual_util_per_1000 as benchmark_util_per1k

	from grouped_avg_risk_scrores as groups
	cross join
		M015_Out.well_managed_benchmarks as well
	;
quit;


/*Stack the loosley-managed and the well-managed benchmarks*/
data stacked_benchmarks;
	set Risk_adj_loose_man_bench (in= a)
		cart_prod_well_man_benchmarks (in=b);

	format name_client $60. type_benchmark $8.;
	
	name_client = &assign_name_client.;
	
	if a then type_benchmark = "Loose";
		else if b then type_benchmark = "Well";
	
run;



