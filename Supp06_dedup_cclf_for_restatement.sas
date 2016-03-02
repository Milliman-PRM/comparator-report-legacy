/*
### CODE OWNERS: Jack Leemhuis

### OBJECTIVE:
  Cut out data from the prior run's CCLF data in the 020 module, so that stacking with restated CCLF data
  will not cause any duplicates.

### DEVELOPER NOTES:
  1) Business logic:
		- A claim is eliminated if the member showed up in both the old and restated CCLF files
		  AND had its paid date during a year that is in the restated CCLF data
  2) BEFORE running this program, a new folder name "production" needs to be created in the location of the old 020 directory.
     Then, move/cut the CCLF files in the old 020 directory into this "production" folder. Finally, copy the CCLF8 and CCLF9
	 files back into the old 020 directory, so that they can be stacked during normal PRM run
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

%AssertThat(&Claims_Elig_Format.,eq,CCLF,ReturnMessage=The claims and eligibility format selected in the driver is not compatible with this program,FailAction=EndActiveSASSession);

/* Libnames */
%let new_cclf = &Path_Project_Received.;
%put new_cclf = &new_cclf.;
libname new_cclf "&new_cclf." access=readonly;

%SetLibrary(&M020_Old.,M020_Old,YES)
%let old_cclf = &M020_Old.;
%put old_cclf = &old_cclf.;
libname old_cclf "&old_cclf.";

%let paid_dt_cutoff = 1,1,2015;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Get a list of members in the restatment files*/

%GetFileNamesfromDir(&Path_Project_Received.,cclf9_file,CCLF9)

proc sql noprint;
	select filename
	into :name_file_CCLF9 trimmed
	from cclf9_file
;
quit;

%put name_file_CCLF9 = &name_file_CCLF9.;

data cclf9;
  infile "&new_cclf.&name_file_CCLF9." lrecl = 54;
  input @; _infile_ = tranwrd(_infile_,"~"," ");
  input @1 crnt_hic_num $11.
    @12 prvs_hic_num $11.
    @23 prvs_hicn_efctv_dt yymmdd10.
    @33 prvs_hicn_obslt_dt yymmdd10.
    @43 bene_rrb_num $12.;

  format prvs_hicn_efctv_dt prvs_hicn_obslt_dt YYMMDD10.;
run;  

data current_id_cclf9 (rename = (crnt_hic_num=bene_hic_num));
	set cclf9;
	keep crnt_hic_num;
run;

data previous_id_cclf9 (rename = (prvs_hic_num=bene_hic_num));
	set cclf9;
	keep prvs_hic_num;
run;

data restatement_members_pre;
	set current_id_cclf9
		previous_id_cclf9
		;
run;

proc summary nway missing data=restatement_members_pre;
	class bene_hic_num;
	output out=restatement_members (drop = _:);
run;

/*Limit CCLF1-9 files*/

/*Find the claims that we want to get rid of for CCLF files that do not contain paid dates
  (i.e. part A procs, diags, and rev codes)*/

*CCLF1 part A header file, and sas dataset with claims that we want to get rid of;
data discarded_claims (drop = line rc_claims);
infile "&old_cclf.production\CCLF1.txt" lrecl = 177; 
file "&old_cclf.CCLF1.txt" lrecl = 177;

input line $177.;
format bene_hic_num $11. clm_idr_ld_dt yymmddd10. cur_clm_uniq_id 13.;

bene_hic_num = substr(line,20,11);
clm_idr_ld_dt = input(substr(line,150,10),yymmdd10.);
cur_clm_uniq_id = substr(line,1,13);


if _n_ eq 1 then do;
	declare hash ht_claims(dataset:"restatement_members",duplicate:"error");
	ht_claims.definekey("bene_hic_num");
	ht_claims.definedone();
	end;
	rc_claims = ht_claims.find();

if rc_claims ne 0 or clm_idr_ld_dt lt mdy(&paid_dt_cutoff.) then do;
	put line;
	end;

else do;
	output discarded_claims;
	end;

run;

*CCLF2 part A revenue codes file;
data _null_;
infile "&old_cclf.production\CCLF2.txt" lrecl = 163; 
file "&old_cclf.CCLF2.txt" lrecl = 163;

input line $163.;
format bene_hic_num $11. cur_clm_uniq_id 13.;

bene_hic_num = substr(line,24,11);
cur_clm_uniq_id = substr(line,1,13);

if _n_ eq 1 then do;
	declare hash ht_cclf(dataset:"discarded_claims",duplicate:"error");
	ht_cclf.definekey("bene_hic_num","cur_clm_uniq_id");
	ht_cclf.definedone();
	end;
	rc_cclf = ht_cclf.find();

if rc_cclf ne 0 then put line;

run;

*CCLF3 part A procedure codes file;
data _null_;
infile "&old_cclf.production\CCLF3.txt" lrecl = 83; 
file "&old_cclf.CCLF3.txt" lrecl = 83;

input line $83.;
format bene_hic_num $11. cur_clm_uniq_id 13.;

bene_hic_num = substr(line,14,11);
cur_clm_uniq_id = substr(line,1,13);

if _n_ eq 1 then do;
	declare hash ht_cclf(dataset:"discarded_claims",duplicate:"error");
	ht_cclf.definekey("bene_hic_num","cur_clm_uniq_id");
	ht_cclf.definedone();
	end;
	rc_cclf = ht_cclf.find();

if rc_cclf ne 0 then put line;

run;

*CCLF4 part A diagnosis codes file;
data _null_;
infile "&old_cclf.production\CCLF4.txt" lrecl = 81; 
file "&old_cclf.CCLF4.txt" lrecl = 81;

input line $81.;
format bene_hic_num $11. cur_clm_uniq_id 13.;

bene_hic_num = substr(line,14,11);
cur_clm_uniq_id = substr(line,1,13);

if _n_ eq 1 then do;
	declare hash ht_cclf(dataset:"discarded_claims",duplicate:"error");
	ht_cclf.definekey("bene_hic_num","cur_clm_uniq_id");
	ht_cclf.definedone();
	end;
	rc_cclf = ht_cclf.find();

if rc_cclf ne 0 then put line;

run;

*CCLF5 part B physicians file;
data _null_;
infile "&old_cclf.production\CCLF5.txt" lrecl = 321; 
file "&old_cclf.CCLF5.txt" lrecl = 321;

input line $321.;
format bene_hic_num $11. clm_idr_ld_dt yymmddd10.;

bene_hic_num = substr(line,24,11);
clm_idr_ld_dt = input(substr(line,151,10),yymmdd10.);

if _n_ eq 1 then do;
	declare hash ht_cclf(dataset:"restatement_members",duplicate:"error");
	ht_cclf.definekey("bene_hic_num");
	ht_cclf.definedone();
	end;
	rc_cclf = ht_cclf.find();

if rc_cclf ne 0 or clm_idr_ld_dt lt mdy(&paid_dt_cutoff.) then put line;

run;

*CCLF6 part B DME file;
data _null_;
infile "&old_cclf.production\CCLF6.txt" lrecl = 216; 
file "&old_cclf.CCLF6.txt" lrecl = 216;

input line $216.;
format bene_hic_num $11. clm_idr_ld_dt yymmddd10.;

bene_hic_num = substr(line,24,11);
clm_idr_ld_dt = input(substr(line,137,10),yymmdd10.);

if _n_ eq 1 then do;
	declare hash ht_cclf(dataset:"restatement_members",duplicate:"error");
	ht_cclf.definekey("bene_hic_num");
	ht_cclf.definedone();
	end;
	rc_cclf = ht_cclf.find();

if rc_cclf ne 0 or clm_idr_ld_dt lt mdy(&paid_dt_cutoff.) then put line;

run;

*CCLF7 part D file;
data _null_;
infile "&old_cclf.production\CCLF7.txt" lrecl = 182; 
file "&old_cclf.CCLF7.txt" lrecl = 182;

input line $182.;
format bene_hic_num $11. clm_idr_ld_dt yymmddd10.;

bene_hic_num = substr(line,14,11);
clm_idr_ld_dt = input(substr(line,152,10),yymmdd10.);

if _n_ eq 1 then do;
	declare hash ht_cclf(dataset:"restatement_members",duplicate:"error");
	ht_cclf.definekey("bene_hic_num");
	ht_cclf.definedone();
	end;
	rc_cclf = ht_cclf.find();

if rc_cclf ne 0 or clm_idr_ld_dt lt mdy(&paid_dt_cutoff.) then put line;

run;


%put System Return Code = &syscc.;
