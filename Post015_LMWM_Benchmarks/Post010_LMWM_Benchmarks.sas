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
				,scores.elig_status_1
				,scores.Avg_Risk_Score
				,loose.*

				/*Calculate risk-adjusted benchmarks*/
				,(loose.admits_per_1000 * scores.Avg_Risk_Score) as RA_Admits_per_1000
				,(loose.annual_util_per_1000 * scores.Avg_Risk_Score) as RA_Util_per_1000
				,(loose.pmpm * scores.Avg_Risk_Score) as RA_PMPM

	from grouped_avg_risk_scrores as scores
	cross join M015_out.loosely_managed_benchmarks as loose	
	;
quit;



