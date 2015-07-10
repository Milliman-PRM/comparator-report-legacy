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
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname post008 "&post008.";

/*What is the minimum months of runout?*/
%let months_runout_min = 2;
%put months_runout_min = &months_runout_min.;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


data time_windows;
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
	inc_start = intnx('month', inc_end, -11, 'beg');

	output;

	time_period = 'Prior';
	paid_thru = intnx('month', paid_thru, -3, 'end');
	inc_end = intnx('month', inc_end, -3, 'end');
	inc_start = intnx('month', inc_start, -3, 'beg');

	output;
	
	time_period = 'Prior';
	paid_thru = intnx('month', paid_thru, -3, 'end');
	inc_end = intnx('month', inc_end, -3, 'end');
	inc_start = intnx('month', inc_start, -3, 'beg');

	output;
	
	time_period = 'Prior';
	paid_thru = intnx('month', paid_thru, -3, 'end');
	inc_end = intnx('month', inc_end, -3, 'end');
	inc_start = intnx('month', inc_start, -3, 'beg');

	output;
	
	time_period = 'Prior';
	paid_thru = intnx('month', paid_thru, -3, 'end');
	inc_end = intnx('month', inc_end, -3, 'end');
	inc_start = intnx('month', inc_start, -3, 'beg');

	output;

run;

data post008.time_windows;
	format &time_windows_cgfrmt.;
	set time_windows;

	where inc_start ge &Date_CredibleStart.;
	&assign_name_client.;

	format
		riskscr_period_type
		$12.
		inc_start_riskscr_features
		inc_end_riskscr_features
		YYMMDDd10.
		;
	if intnx('month', inc_start, -12, 'beg') ge &Date_CredibleStart. then do;
		riskscr_period_type = 'Prospective';
		inc_start_riskscr_features = intnx('month', inc_start, -3, 'beg');
		inc_end_riskscr_features = intnx('month', inc_end, -3, 'end');
		end;
	else do;
		riskscr_period_type = 'Concurrent';
		inc_start_riskscr_features = inc_start;
		inc_end_riskscr_features = inc_end;
		end;

	keep &time_windows_cgflds.;

run;
%LabelDataSet(post008.time_windows)

%AssertDataSetPopulated(post008.time_windows,ReturnMessage=Not enough data was likely provided to compute meaningful metrics for any time period.)

%put System Return Code = &syscc.;
