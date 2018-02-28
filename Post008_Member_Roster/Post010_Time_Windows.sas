/*
### CODE OWNERS: Shea Parkes, Kyle Baird, Sarah Prusinski

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

%let historical_cutoff = mdy(1,1,2014);
%put &=historical_cutoff.;


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


data time_windows;
	format
		time_period $16.
		inc_start
		inc_end
		paid_thru
		YYMMDDd10.
		;

	paid_thru = &Date_LatestPaid_Round.;
	inc_end = intnx('month', paid_thru, -&months_runout_min., 'end');

	/*Now round to nearest calendar quarter.*/
	inc_end = intnx('month', inc_end, -mod(month(inc_end), 3), 'end');
	inc_start = intnx('month', inc_end, -11, 'beg');

	time_period = cats(
		year(inc_start), 'Q', ceil(month(inc_start)/3)
		,'_'
		,year(inc_end), 'Q', ceil(month(inc_end)/3)
		);

	output;

	do while(intnx('month', inc_start, -3, 'beg') ge max(&Date_CredibleStart., &historical_cutoff.));

		paid_thru = intnx('month', paid_thru, -3, 'end');
		inc_end = intnx('month', inc_end, -3, 'end');
		inc_start = intnx('month', inc_start, -3, 'beg');
		time_period = cats(
			year(inc_start), 'Q', ceil(month(inc_start)/3)
			,'_'
			,year(inc_end), 'Q', ceil(month(inc_end)/3)
			);
		output;

	end;
	
run;

data post008.time_windows;
	format &time_windows_cgfrmt.;
	set time_windows;

	where inc_start ge max(&Date_CredibleStart., &historical_cutoff.);
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
		inc_start_riskscr_features = intnx('month', inc_start, -12, 'beg');
		inc_end_riskscr_features = intnx('month', inc_end, -12, 'end');
		end;
	else do;
		riskscr_period_type = 'Concurrent';
		inc_start_riskscr_features = inc_start;
		inc_end_riskscr_features = inc_end;
		end;

	keep &time_windows_cgflds.;

run;

data post008.time_windows;
	set post008.time_windows;

	where time_period = '2016Q4_2017Q3';
run;

%LabelDataSet(post008.time_windows)

%AssertDataSetPopulated(post008.time_windows,ReturnMessage=Not enough data was likely provided to compute meaningful metrics for any time period.)

/*%AssertRecordCount(post008.time_windows,eq,%GetRecordCount(time_windows),ReturnMessage=Time_Period construction loop does not have exit condition that matches ultimate filter condition.)*/

%put System Return Code = &syscc.;
