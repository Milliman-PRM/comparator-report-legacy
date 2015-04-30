/*
### CODE OWNERS: Anders Larson, Anna Chen, Jack Leemhuis

### OBJECTIVE:
	Create some final discharge summaries to merge with the readmission rates table for the final discharge analysis results.

### DEVELOPER NOTES:
  1) 

*/


/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/


*Summarize paid amount, number of admits, and number of admit days by discharge status and aco type from grouped claims;
proc summary nway missing data = elig_claims;
class dischargestatus prv_name;
var prm_costs admits prm_util;
output out = discharge_totals (drop= _freq_ _type_) sum=;
run;

proc summary nway missing data = elig_claims;
class DRG_Description_ID prv_name dischargestatus;
var admits;
output out = drg_totals (drop= _type_ _freq_) sum=;
run;

proc sort data = drg_totals;
by prv_name dischargestatus;
run;


*************************************/

*Create a table with every DRG/Hospital combination;
proc summary nway missing data = drg_totals;
class DRG_Description_ID;
var admits;
output out = drg_totals_by_DRG (drop= _type_ _freq_) sum=;
run;

*Limit to those hospitals with at least the given number of admissions;
proc sql;
	create table all_combos as select 
		a.DRG_Description_ID
		,b.prv_name
		,a.admits
	from drg_totals_by_DRG  as a, provider_admits_summ_limit as b
	order by b.prv_name, a.DRG_Description_ID
  	;
quit;

*Bring in Discharnge Status for both provider_admits_summ_limit and provider_other_summ;
proc sql;
	create table provider_disc as
	select b.DRG_description_ID, a.prv_name, b.DischargeStatus, b.admits
	from provider_admits_summ_limit as a
	left join elig_claims as b
		on a.prv_name = b.prv_name
	order by prv_name, DRG_description_ID, admits desc;
quit;

proc summary nway missing data = provider_disc;
class prv_name DRG_Description_ID dischargestatus;
var admits;
output out = provider_disc_summ (drop= _type_ _freq_) sum=;
run;

proc sort data = provider_disc_summ;
by prv_name DRG_Description_ID;
run;


*Group by categ and make a table for each of the categs and flip the table;
data Full_List;
format prv_name DRG_Description_ID dischargestatus admits;
set provider_disc_summ;
where DRG_Description_ID ne '';
run;

proc sort data = Full_List;
by prv_name DRG_Description_ID dischargestatus descending admits;
run;

proc transpose data = Full_List
			   out = Flipped_Full_List_tmp_pre (drop = admits)
			   name = admits;
	by prv_name DRG_Description_ID;
	id dischargestatus;
run;

*Create a list of distinct discharge status codes, to be used in the following format clause.
 The transpose above turned these codes into variables, so we now can format this list of variables;
proc sql noprint; 
     select distinct cat('_',DischargeStatus)
     into : dis_status_format separated by ' '
     from Full_List
;
quit;

%put dis_status_format = &dis_status_format.;

*Create a list of distinct discharge status codes, to be used in the following sum clause.
 The transpose above turned these codes into variables, so we now can sum this list of variables;
proc sql noprint; 
     select distinct cat('_',DischargeStatus)
     into : dis_status_sum separated by ','
     from Full_List
;
quit;

%put dis_status_sum = &dis_status_sum.;


data Flipped_Full_List_tmp (drop = i_fill);
format prv_name DRG_Description_ID &dis_status_format. Total_Admits;
set Flipped_Full_List_tmp_pre;
array all_nums(*) _numeric_;
	do i_fill = 1 to dim(all_nums);
	if all_nums(i_fill) eq . then all_nums(i_fill)=0;
	end;
Total_Admits = sum(&dis_status_sum.);
run;

*Merge Flipped_Full_List_Temp with All_Combos of DRG/Hospital;
data Merge_Full_List;
merge Flipped_Full_List_tmp (in = a)
	  all_combos (in = b);
by prv_name DRG_Description_ID;
run;

*Limit drg_totals to only the providers we want;
Proc SQl;
	Create Table drg_totals_limited as 
		Select a.*
		from drg_totals (where = (DRG_Description_ID ne '')) as a
		inner join  provider_admits_summ_limit as b
			on A.prv_name = b.prv_name;
Quit;

*Export admit totals by DRG Group for all providers;
proc summary nway missing data = drg_totals_limited (where = (DRG_Description_ID ne ''));
class DRG_Description_ID;
var admits;
output out = admits_by_drg (drop = _type_ _freq_)sum=;
run;

*Calculate the total admits;
proc sql noprint;
	select sum(admits)
	into :obssum
	from admits_by_drg;
quit;

%put sum = &obssum;


*Limit discharge totals to only the providers we want;
Proc SQl;
	Create Table Discharge_Totals_limited as 
		Select a.*
		FROM Discharge_Totals as a
		inner join  provider_admits_summ_limit as b
			on A.prv_name = b.prv_name;
Quit;

*Normalized with composite data when single pct_adm is 0;
*First calculate the composite percentage data;
proc sql noprint;
	select sum(PRM_Costs)
	into :Paysum
	from Discharge_Totals_limited;
quit;

%put sum = &Paysum;

proc sql noprint;
	select sum(admits)
	into :Admitsum
	from Discharge_Totals_limited;
quit;

%put sum = &Admitsum;

proc summary nway missing data = Discharge_Totals_limited;
class DischargeStatus;
var PRM_Costs admits;
output out = Discharge_tot_by_disch_status (drop = _type_ _freq_) sum=;
run;

data Discharge_tot;
format DischargeStatus $5.;
set Discharge_tot_by_disch_status;
Paid_pct = PRM_Costs /&Paysum.;
Admits_pct = admits / &Admitsum.;
if DischargeStatus not in ("01","03","06") then DischargeStatus = "Other";
run;

proc summary nway missing data = Discharge_tot;
class DischargeStatus;
var Admits_pct Paid_pct;
output out = Discharge_tot_summ (drop = _type_ _freq_) sum=;
run;

proc transpose data = Discharge_tot_summ (drop = Paid_pct)
			   out = Discharge_tot_summ_flipped ( rename = (_01 = _01_adm_pct _03 = _03_adm_pct _06 = _06_adm_pct Other = Other_adm_pct));
	var Admits_pct;
	id DischargeStatus;
run;

*Create macro variables for the Discharge_tot_summ_flipped;
proc sql noprint;
	select sum(_01_adm_pct)
	into :_01_avg
	from Discharge_tot_summ_flipped;
quit;

%put sum = &_01_avg;

proc sql noprint;
	select sum(_03_adm_pct)
	into :_03_avg
	from Discharge_tot_summ_flipped;
quit;

%put sum = &_03_avg;

proc sql noprint;
	select sum(_06_adm_pct)
	into :_06_avg
	from Discharge_tot_summ_flipped;
quit;

%put sum = &_06_avg;

proc sql noprint;
	select sum(Other_adm_pct)
	into :_other_avg
	from Discharge_tot_summ_flipped;
quit;

%put sum = &_other_avg;



*Create the full distribution table;
data Distribution_tmp (drop = admits);
format prv_name DRG_Description_ID &dis_status_format. Total_Admits Other_Total Total_Across_All_Providers _01_pct _03_pct _06_pct Other_pct;
set merge_full_list;
Other_Total = Total_Admits - sum(_01, _03, _06);

Total_Across_All_Providers = admits;

/*if _01 in (.,0) then _01_pct = &_01_avg.;
else _01_pct = _01 / Total_Admits;

if _03 in (.,0) then _03_pct = &_03_avg.;
else _03_pct = _03 / Total_Admits;

if _06 in (.,0) then _06_pct = &_06_avg.;
else _06_pct = _06 / Total_Admits;

if Total_Admits in (.,0) then Other_pct = &_other_avg.;
else Other_pct = Other_Total / Total_Admits;*/

if Total_Admits in (.,0) then do;
	_01_pct = &_01_avg.;
	_03_pct = &_03_avg.;
	_06_pct = &_06_avg.;
	Other_pct = &_other_avg.;
	end;
else do;
_01_pct = _01 / Total_Admits;
_03_pct = _03 / Total_Admits;
_06_pct = _06 / Total_Admits;
Other_pct = Other_Total / Total_Admits;
end;
run;

data Distribution;
format prv_name DRG_Description_ID &dis_status_format. Total_Admits Other_Total Total_Across_All_Providers 
       _01_pct _01_adm _03_pct _03_adm _06_pct _06_adm Other_pct Other_adm Total_pct;
set Distribution_tmp;
_01_adm = _01_pct * Total_Across_All_Providers;
_03_adm = _03_pct * Total_Across_All_Providers;
_06_adm = _06_pct * Total_Across_All_Providers;
Other_adm = Other_pct * Total_Across_All_Providers;
Total_pct = _01_pct + _03_pct + _06_pct + Other_pct;
run;

proc sort data = Distribution;
by prv_name;
run;

/****************************************************************************************************************
****************************************************************************************************************
****************************************************************************************************************
****************************************************************************************************************
****************************************************************************************************************/

*Import Discharge status codes;
proc import out=Disc_status_codes (rename = (code = DischargeStatus structure = Discharge_Description))
	datafile="%GETPARENTFOLDER(1)Reference\Discharge_Status_Codes.xlsb" 
	dbms=excel replace;
	sheet='ForSAS'; 
run;

*Make a summary table for DRG distribution;
data summary_full_list_temp;
format DischargeStatus $5. prv_name PRM_Costs admits prm_util;
set Discharge_Totals;
if DischargeStatus not in ("01", "03", "06") then DischargeStatus = "Other";
run;

proc summary nway missing data= Summary_full_list_temp;
class DischargeStatus prv_name;
var PRM_Costs admits prm_util;
output out = Summary_full_list (drop = _type_ _freq_) sum=;
run;

*Sum the paid, mr_cases_admits and mr_units_days by provider and categ;
proc summary nway missing data = Discharge_totals;
class prv_name;
var PRM_Costs admits prm_util;
output out = Discharge_totals_by_provider (rename = (PRM_Costs = paid_by_provider admits = mr_cases_by_provider prm_util = mr_days_by_provider) drop = _type_ _freq_) sum=;
run;

*Merge the Summary_Full_List with Discharge_totals_by_provider information;
proc sql;
	create table summary_merge as
	select a.DischargeStatus, a.prv_name, a.PRM_Costs, a.admits, a.prm_util, b.paid_by_provider, b.mr_cases_by_provider, b.mr_days_by_provider
	from summary_full_list as a 
	left join Discharge_totals_by_provider as b
		on a.prv_name = b.prv_name;
quit;

*Add in summary by dischagre code for overall paid and overall mr_cases_admits. Then name name the prv_name "Total";
proc sql;
	create table summary_merge_tot as
	select a.DischargeStatus, a.prv_name, a.PRM_Costs, a.admits, a.prm_util, c.paid_by_provider, c.mr_cases_by_provider, c.mr_days_by_provider
	from summary_full_list as a 
		inner join provider_admits_summ_limit as b
		on a.prv_name = b.prv_name
		left join Discharge_totals_by_provider as c
		on a.prv_name = c.prv_name;
quit;

proc summary nway missing data = summary_merge_tot;
class DischargeStatus;
var PRM_Costs admits;
output out = summary_merge_summ (drop = _type_ _freq_) sum=;
run;

data summary_merge_summ_mod;
format DischargeStatus prv_name PRM_Costs admits;
set summary_merge_summ;
prv_name = "Total";
run;

proc sql noprint;
	select sum(PRM_Costs)
	into : tot_paid
	from summary_merge_summ_mod;
quit;

%put sum = &tot_paid;

proc sql noprint;
	select sum(admits)
	into : tot_admits
	from summary_merge_summ_mod;
quit;

%put sum = &tot_admits;

data summary_merge_temp;
format DischargeStatus prv_name $55. PRM_Costs paid_pct admits mr_cases_admits_pct;
set summary_merge_summ_mod;
paid_pct = PRM_Costs / &tot_paid.;
mr_cases_admits_pct = admits / &tot_admits.;
run;

proc sort data = summary_merge_temp;
by prv_name DischargeStatus;
run;

*Add in percentage into Summary_merge dataset;
data summary_merge_mod (drop = prm_util paid_by_provider mr_cases_by_provider mr_days_by_provider);
format DischargeStatus prv_name PRM_Costs paid_pct admits mr_cases_admits_pct;
set summary_merge;
paid_pct = PRM_Costs / paid_by_provider;
mr_cases_admits_pct = admits / mr_cases_by_provider;
run;

proc sort data = summary_merge_mod;
by prv_name DischargeStatus;
run;


*Then add in other normalized admits for All DRG;
proc summary nway missing data = distribution;
class prv_name;
var Total_Across_All_Providers _01_adm _03_adm _06_adm Other_adm;
output out = distribution_summ_3 (drop = _type_ _freq_) sum=;
run;

data distribution_summ_4;
format prv_name Total_Across_All_Providers _01_adm _01_adm_pct _03_adm _03_adm_pct _06_adm _06_adm_pct Other_adm Other_adm_pct Total_pct;
set distribution_summ_3;
_01_adm_pct = _01_adm / Total_Across_All_Providers;
_03_adm_pct = _03_adm / Total_Across_All_Providers;
_06_adm_pct = _06_adm / Total_Across_All_Providers;
Other_adm_pct = Other_adm / Total_Across_All_Providers;
Total_pct = _01_adm_pct + _03_adm_pct + _06_adm_pct + Other_adm_pct; *Used to check if the percentages add up to 1;
run;

proc transpose data = distribution_summ_4
			   out = distr_flipped
			   prefix = pct_adm_norm_TopDRG;
	var _01_adm_pct _03_adm_pct _06_adm_pct Other_adm_pct;
	by prv_name;
run;

data distr_flipped_pct (drop = _NAME_);
format DischargeStatus $5. prv_name pct_adm_norm_TopDRG;
set distr_flipped (rename = (pct_adm_norm_TopDRG1 = pct_adm_norm_TopDRG_All));
if _NAME_ eq "Other_adm_pct" then DischargeStatus = "Other";
else DischargeStatus = substr(_NAME_,2,2);
run;

proc sort data = distr_flipped_pct;
by prv_name DischargeStatus;
run;

*Keep mr_cases_admits;
data Table_Full_List_Temp (drop = PRM_Costs /*mr_units_days*/);
format DischargeStatus prv_name admits paid_pct mr_cases_admits_pct pct_adm_norm_TopDRG_All;
merge summary_merge_mod (in = a)
	  distr_flipped_pct (in = c);
by prv_name DischargeStatus;
if c;
run;

proc sql;
	create table Final_Table_Temp as
	select a.DischargeStatus, b.Discharge_Description, a.prv_name, a.admits, a.paid_pct, a.mr_cases_admits_pct, a.pct_adm_norm_TopDRG_All
	from Table_Full_List_temp as a
	left join Disc_status_codes as b
		on a.DischargeStatus = b.DischargeStatus
;
quit;

proc sort data = Final_Table_Temp;
by prv_name DischargeStatus;
run;


*2;
proc summary nway missing data = Distribution;
var Total_Across_All_Providers _01_adm _03_adm _06_adm Other_adm;
output out = Distribution_summ_tot_3 (drop = _type_ _freq_) sum=;
run;

data Distribution_summ_tot_4;
format prv_name Total_Across_All_Providers _01_adm _01_adm_pct _03_adm _03_adm_pct _06_adm _06_adm_pct Other_adm Other_adm_pct Total_pct;
set Distribution_summ_tot_3;
prv_name = "Total";
_01_adm_pct = _01_adm / Total_Across_All_Providers;
_03_adm_pct = _03_adm / Total_Across_All_Providers;
_06_adm_pct = _06_adm / Total_Across_All_Providers;
Other_adm_pct = Other_adm / Total_Across_All_Providers;
Total_pct = _01_adm_pct + _03_adm_pct + _06_adm_pct + Other_adm_pct; *Used to check if the percentages add up to 1;
run;

proc transpose data = Distribution_summ_tot_4
			   out = distr_flipped_tot
			   prefix = pct_adm_norm_TopDRG;
	var _01_adm_pct _03_adm_pct _06_adm_pct Other_adm_pct;
	by prv_name;
run;

data distr_flipped_pct_tot (drop = _NAME_);
format DischargeStatus $5. prv_name pct_adm_norm_TopDRG;
set distr_flipped_tot (rename = (pct_adm_norm_TopDRG1 = pct_adm_norm_TopDRG_All));
if _NAME_ eq "Other_adm_pct" then DischargeStatus = "Other";
else DischargeStatus = substr(_NAME_,2,2);
run;

proc sort data = distr_flipped_pct_tot;
by prv_name DischargeStatus;
run;

data Table_Full_List_Tot;
format DischargeStatus prv_name admits paid_pct mr_cases_admits_pct pct_adm_norm_TopDRG pct_adm_norm_TopDRG_All;
merge summary_merge_Temp (in = a)
	  distr_flipped_pct_tot (in = c);
by prv_name DischargeStatus;
if c;
run;

proc sql;
	create table Final_Table_Tot as
	select a.DischargeStatus, b.Discharge_Description, a.prv_name, a.admits, a.paid_pct, a.mr_cases_admits_pct, a.pct_adm_norm_TopDRG_All
	from Table_Full_List_Tot as a
	left join Disc_status_codes as b
		on a.DischargeStatus = b.DischargeStatus
;
quit;

proc sort data = Final_Table_Tot;
by prv_name DischargeStatus;
run;

*Finally, combine all the information into Final_Table_pre;
data Final_Table_pre;
format prv_name $128.;
set Final_Table_Tot
	Final_Table_Temp;
run;

*Flip the table to reflect the layout in pdf file;
*First work with the normalized rate;

proc sort data = Final_Table_pre;
by prv_name;
run;

proc transpose data = Final_Table_pre (keep = DischargeStatus prv_name pct_adm_norm_TopDRG_All)
			   out = Disch_norm_rate  
					(drop = _NAME_ rename = ( _01=Norm_Disch_to_Home _03=Norm_Disch_to_SNF _06=Norm_Disch_to_HomeHealth_Care Other=Norm_Other_Disch));
	by prv_name;
	id DischargeStatus;
	var pct_adm_norm_TopDRG_All;
run;

*Similar process apply to observed rate;
proc transpose data = Final_Table_pre (keep = DischargeStatus prv_name mr_cases_admits_pct)
			   out = Disch_Obs_rate   
					(drop = _NAME_ rename = ( _01=Obs_Disch_to_Home _03=Obs_Disch_to_SNF _06=Obs_Dischto_HomeHealth_Care Other=Obs_other_Disch));
	by prv_name;
	id DischargeStatus;
	var mr_cases_admits_pct;
run;

*Calculate the numbers of admission by provider. The discharges will not match up with those on the Readmission program b/c the other program
 removes rehab facilities and transfers;
proc summary nway missing data = Final_table_pre;
	class prv_name;
	var admits;
	output out = Final_admits_summ (drop = _type_ _freq_) sum=;
run;

*Now, merge the observed rate, normalized rate and numbers of admits tables together;
data Disch_Final_table;
	merge Disch_Obs_rate (in = a)
		  Disch_norm_rate (in = b)
		  Final_admits_summ (in = c);
	by prv_name;
	if a and b and c;

*Due to the way the normalized calculations work, the normalized totals will not match the observed totals.  
 Set the normalized totals equal to the observed totals for the Total line only;
	if prv_name eq 'Total' then do;
		Norm_Disch_to_Home = Obs_Disch_to_Home;
		Norm_Disch_to_SNF = Obs_Disch_to_SNF;
		Norm_Disch_to_HomeHealth_Care = Obs_Dischto_HomeHealth_Care;
		Norm_Other_Disch = Obs_Other_Disch;
	end;
*Also, if there are no observations, then delete the normalized results to eliminate confusion;
	if Obs_Disch_to_Home in (0,.) then Norm_Disch_to_Home = .;
	if Obs_Disch_to_SNF in (0,.) then Norm_Disch_to_SNF = .;
	if Obs_Dischto_HomeHealth_Care in (0,.) then Norm_Disch_to_HomeHealth_Care = .;
	if Obs_Other_Disch in (0,.) then Norm_Other_Disch = .;
run;



%put System Return Code = &syscc.;

