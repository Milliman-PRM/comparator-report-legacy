#Release Notes

## v6.2.1

### Client Visible Changes
 - Limited metric time periods to 2014 onwards

### Logic Changes
 - Added `Cone Health` as a NextGen client
 - Utilized the exclusion files to remove NextGen members from the assigned list

## v6.2.0

### Client Visible Changes
 - Added script to copy CCLF data to the NewYorkMillimanShare
 - Added flatfile datamart to be provided to external clients
 - Added `members`, `member_time`, `outclaims_prm`, and `outpharmacy_prm` to the standard deliverable
 - Calculated and added `member_riskscores` and `member_riskscr_coeffs` to standard outputs

### Logic Changes
 - Replace built in MSSP assignment logic with `prmclient-library`
 - Added NextGen assignment logic
 - Change `select` to `select distinct` when creating passround table
 - Update the `post010.member_elig` table to use the monthly elgibility status flags from the `QASSGN` files


### Lower Level Changes
 - Updated `meta_field_label` length to match v6.2.x of the `analytics-pipeline`
 - Exempted NextGen from the `pct_assigned_in_cclf` assertion because assignment is partially derived from the CCLF data
 - Added `project_namespace` to `stage_data_drive.py`
 - Loosen assertion that the member level and aggregate reports match due to slight differences in exclusion logic
 - Moved all deliverable movement to the NewYorkMillimanShare to `post090_output_deliverables`
 - Added `Fix_ICD_Version` and `Fix_Outclaims_PRM` to correct data issues with Pioneer and NextGen clients
 - Organized Pioneer specific programs into `Supp_NextGen_Pioneer_Programs` subfolder
 - Organized report split programs into `Report_Split_Programs` subfolder
 - Disabled MARA API instead of updating to Spark API
 - Set up dummy deliverable location `TestShare`

## v6.1.3

### Client Visible Changes
 - *none*

### Logic Changes
 - *none*

### Lower Level Changes
 - Updated assignment scraping code to use correct casing when identifying prospective HASSGN files

## v6.1.2

### Client Visible Changes
 - *none*

### Logic Changes
 - *none*

### Lower Level Changes
 - Updated assignment scraping code to ignore the word `Prospective` for QASSGN files

## v6.1.1

### Client Visible Changes
 - Use `PRM_Paid` rather than `PRM_Costs` in the `member_costs` table.

### Logic Changes
 - *none*
 
### Lower Level Changes
 - Make `date_end` the maximum of the `date_start` and calculated `date_end` for Pioneers

## v6.1.0

### Client Visible Changes
 - Added `Member_Cost` table to postboarding datamart
 - Created `outclaims_w_prv` with the following additional fields:
  - `CCN`
  - `attending_prv_npi`
  - `operating_prv_npi`

### Logic Changes 
 - *none*

### Lower Level Changes
 - Loosened zero member months assertion and change to `notify_only`
 - Add zombie periods for pioneers

## v6.0.0

### Client Visible Changes
 - Added member level reporting for CaroMont for the following metrics:
  - Preventable ED
  - Ambulatory Sensitive Admissions for Heart Failure
  - Part B Drug Expense and Utilization (non-chemo)
 
###  Logic Changes
 - *none* 

### Lower Level Changes
 - Removed reference to retired ```prm_parser```
 - Updated report split program to call postboarding libraries after assignment
 - Updated output renaming code to properly handle ```_all``` datasets


## v5.2.0

### Client Visible Changes (e.g. Updates to the Comparator Report Datamart)
- Added readmission and cancer denominator counts
- Added a claims probability distribution to the output datamart
- Added an office administered drug summary to the output datamart
- Added a count of members without runout at the end of 2015 (applicable to the 201603 run only)

### Logic Changes
- *none*

### Lower Level Changes
- *none*

## v5.1.2
  - Munge the `sys.path` in disk cleanup because the new python parser no longer does so for you. This allows functions to be imported from the main analytics-pipeline `disk_cleanup` script

## v5.1.1
  - Re-instated the `Path()` call in Wrap-Up so the resulting object would `Path` object as expected by the program

## v5.1.0

### Client Visible Changes (e.g. Updates to the Comparator Report Datamart)
- *none*

### Logic Changes
- Updated Pioneer logic to create client member time based on the presence of claims in a given year

### Lower Level Changes
- Derive the most recent Beneficiary Exclusion file
- Fixed the market split naming code to only append the current market name
- Update to new python parser


## v5.0.0

#### Client Visible Changes (e.g. Updates to the Comparator Report Datamart)
- *none*

#### Logic Changes
- Use component MARA risk scores (this will not impact NYP)

#### Lower Level Changes
- Updated postboarding datamart creation script to be compatible with analytics-pipeline v5.11
