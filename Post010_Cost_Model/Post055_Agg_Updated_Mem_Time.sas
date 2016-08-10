/*
### CODE OWNERS: Brandon Patterson, Jason Altieri

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
	select
		old_elig.member_id
		,old_elig.elig_status_1
		,old_elig.elig_month
		,old_elig.memmos
		,new_elig.elig_status as hassgn_elig_status
	from M018_Out.monthly_elig_status as new_elig
	right join M035_Out.member_time as old_elig
	on
		old_elig.member_id eq new_elig.hicno
		and new_elig.date_elig_start + 14 eq old_elig.elig_month
	where cover_medical = 'Y'
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
	select elig.member_id, window.time_period, elig.elig_month, elig.new_elig as elig_status, elig.memmos
	from full_elig as elig
	cross join post008.time_windows as window
	where elig.elig_month between window.inc_start and window.inc_end
	;
quit;

proc sql;
	create table post010.member_elig as
	select 
			"&name_client." as name_client format $256. length 256,
			src.member_id, 
			src.time_period, 
			src.elig_status as elig_status_1, 
			sum(src.memmos) as elig_months
	from full_elig_windowed as src
	inner join post008.members as limit on
		src.member_id eq limit.member_id
		and src.time_period eq limit.time_period
	group by src.elig_status, src.member_id, src.time_period
	order by src.member_id, src.time_period
	;
quit;

%LabelDataSet(post010.member_elig)

/*Assert that memmos match the member roster*/
proc summary nway missing data=post008.members;
	class member_id time_period;
	var memmos;
	output out = base_test (drop = _:)sum=;
run;

proc summary nway missing data=post010.member_elig;
	class member_id time_period;
	var elig_months;
	output out=elig_memmos (drop = _:)sum=elig_memmos;
run;

proc sql;
	create table memmos_mismatch as
	select
		base.member_id
		,base.time_period
		,round(base.memmos,.01) as base_memmos
		,new.elig_memmos as new_memmos
	from base_test as base
	full outer join elig_memmos as new
		on base.member_id = new.member_id and
		base.time_period = new.time_period

	;
quit;

%put System Return Code = &syscc.;
