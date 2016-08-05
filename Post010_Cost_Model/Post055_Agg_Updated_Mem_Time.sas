/*
### CODE OWNERS: Brandon Patterson

### OBJECTIVE:
	Create sas dataset with the monthly eligibility status data from the Q/H-Assigns,
		using member_time data to fill in any holes.
	Aggregate updated times by time windows of interest

### DEVELOPER NOTES:

*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname M018_Out "&M018_Out." access=readonly;
libname M035_Out "&M035_Out." access=readonly;
libname post008 "&post008." access=readonly;
libname post010 "&post010.";

proc sql;
	create table elig_map as
	select distinct
		old_elig.*
		,new_elig.elig_status as hassgn_elig_status
	from M018_Out.monthly_elig_status as new_elig
	right join
	(
		select member_id, elig_status_1, elig_month
		from M035_Out.member_time
	) as old_elig
	on
		old_elig.member_id eq new_elig.hicno
		and new_elig.date_elig_start + 14 eq old_elig.elig_month
	order by member_id, elig_month desc
	;
quit;

data full_elig;
	set elig_map;
	by member_id;
	format prv_elig new_elig $64.;
	retain prv_elig;
	if first.member_id then do;
		new_elig = coalescec(hassgn_elig_status, elig_status_1);
		prv_elig = new_elig;
	end;
	else do;
		new_elig = coalescec(hassgn_elig_status, prv_elig);
		prv_elig = new_elig;
	end;
run;

proc sql;
	create table full_elig_windowed as
	select elig.member_id, window.time_period, elig.elig_month, elig.new_elig as elig_status
	from full_elig as elig
	cross join post008.time_windows as window
	where elig.elig_month between window.inc_start and window.inc_end
	;
quit;

proc sql;
	create table elig_counts_long as
	select member_id, time_period, elig_status, count(*) as elig_months
	from full_elig_windowed
	group by elig_status, member_id, time_period
	order by member_id, time_period
	;
quit;

proc transpose
		data=elig_counts_long
		out=elig_counts(drop=_name_)
		prefix=months_
		;
	by member_id time_period;
	id elig_status;
	var elig_months;
run;

data elig_counts_summed;
	set elig_counts;
	months_total = 
	coalesce(months_aged_non_dual, 0)
	+ coalesce(months_disabled, 0)
	+ coalesce(months_aged_dual, 0)
	+ coalesce(months_esrd, 0)
	;
run;

data post010.elig_summary;
	set elig_counts_summed;
run;

%LabelDataSet(post010.elig_summary)

%put System Return Code = &syscc.;
