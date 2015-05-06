/*
### CODE OWNERS: Shea Parkes, Kyle Baird

### OBJECTIVE:
	Define time windows of interest in Comparator Reporting.

### DEVELOPER NOTES:
	None
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;

libname post008 "&post008.";

/*What is the minimum months of runout?*/
%let months_runout_min = 2;
%put months_runout_min = &months_runout_min.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


data post008.time_windows;
	format
		time_period $16.
		inc_start
		inc_end
		paid_thru
		YYMMDDd10.
		;

	time_period = 'Current';
	paid_thru = &Date_LatestPaid_Round.;
	inc_end = intnx('month', paid_thru, -&months_runout_min., 'end');

	/*Now round to nearest calendar quarter.*/
	inc_end = intnx('month', inc_end, -mod(month(inc_end), 3), 'end');
	inc_start = intnx('month', inc_end, -12, 'beg');

	output;

	time_period = 'Prior';
	paid_thru = intnx('month', paid_thru, -12, 'end');
	inc_end = intnx('month', inc_end, -12, 'end');
	inc_start = intnx('month', inc_start, -12, 'beg');

	output;

run;

%LabelDataSet(post008.time_windows)

%put System Return Code = &syscc.;
