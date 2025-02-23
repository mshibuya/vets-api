# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
PERIODIC_JOBS = lambda { |mgr|
  mgr.tz = ActiveSupport::TimeZone.new('America/New_York')

  mgr.register('*/15 * * * *', 'CovidVaccine::ScheduledBatchJob')
  mgr.register('*/15 * * * *', 'CovidVaccine::ExpandedScheduledSubmissionJob')
  mgr.register('*/30 * * * *', 'SidekiqAlive::CleanupQueues')

  mgr.register('5 * * * *', 'AppealsApi::HigherLevelReviewUploadStatusBatch')
  # Update HigherLevelReview statuses with their Central Mail status
  mgr.register('10 * * * *', 'AppealsApi::NoticeOfDisagreementUploadStatusBatch')
  # Update NoticeOfDisagreement statuses with their Central Mail status
  mgr.register('15 * * * *', 'AppealsApi::SupplementalClaimUploadStatusBatch')
  # Update SupplementalClaim statuses with their Central Mail status
  mgr.register('45 0 * * *', 'AppealsApi::HigherLevelReviewCleanUpWeekOldPii')
  # Remove PII of HigherLevelReviews that have 1) reached one of the 'completed' statuses and 2) are a week old
  mgr.register('45 0 * * *', 'AppealsApi::NoticeOfDisagreementCleanUpWeekOldPii')
  # Remove PII of NoticeOfDisagreements that have 1) reached one of the 'completed' statuses and 2) are a week old
  mgr.register('45 0 * * *', 'AppealsApi::SupplementalClaimCleanUpPii')
  # Ensures that appeal evidence received "late" (after the appeal has reached "success") is submitted to Central Mail
  mgr.register('30 * * * *', 'AppealsApi::EvidenceSubmissionBackup')
  # Remove PII of SupplementalClaims that have 1) reached one of the 'completed' statuses and 2) are a week old
  mgr.register('0 23 * * 1-5', 'AppealsApi::DecisionReviewReportDaily')
  # Daily report of appeals submissions
  mgr.register('0 23 * * 1-5', 'AppealsApi::DailyErrorReport')
  # Daily report of appeals errors
  mgr.register('0 8 * * 1-5', 'AppealsApi::DailyStuckRecordsReport')
  # Daily report of all stuck appeals submissions
  mgr.register('0 23 * * 7', 'AppealsApi::DecisionReviewReportWeekly')
  # Weekly report of appeals submissions
  mgr.register('0 5 * * 1', 'AppealsApi::WeeklyErrorReport')
  # Weekly CSV report of errored appeal submissions
  mgr.register('0 0 1 * *', 'AppealsApi::MonthlyStatsReport')
  # Email a decision reviews stats report for the past month to configured recipients first of the month
  mgr.register('0 2,9,16 * * 1-5', 'AppealsApi::FlipperStatusAlert')
  # Checks status of Flipper features expected to be enabled and alerts to Slack if any are not enabled

  mgr.register('0 0 * * *', 'BenefitsIntakeStatusJob')
  # Updates status of FormSubmissions per call to Lighthouse Benefits Intake API

  # mgr.register('0 0 * * *', 'VRE::CreateCh31SubmissionsReportJob')

  mgr.register('0 0 * * *', 'EducationForm::DeleteOldApplications')
  # Clear out processed 22-1990 applications that are older than 1 month

  mgr.register('20 0 * * *', 'TestUserDashboard::DailyMaintenance')
  # Checks in TUD users that weren't properly checked in.
  mgr.register('0 0 1 */3 *', 'IncomeLimits::GmtThresholdsImport')
  # Import income limit data CSVs from S3
  mgr.register('0 0 1 */3 *', 'IncomeLimits::StdCountyImport')
  # Import income limit data CSVs from S3
  mgr.register('0 0 1 */3 *', 'IncomeLimits::StdIncomeThresholdImport')
  # Import income limit data CSVs from S3
  mgr.register('0 0 1 */3 *', 'IncomeLimits::StdStateImport')
  # Import income limit data CSVs from S3
  mgr.register('0 0 1 */3 *', 'IncomeLimits::StdZipcodeImport')
  # Import income limit data CSVs from S3

  mgr.register('0 2 * * *', 'EVSS::DeleteOldClaims')
  # Clear out EVSS disability claims that have not been updated in 24 hours
  mgr.register('20 2 * * *', 'DeleteOldPiiLogsJob')
  # Clear out old personal information logs
  mgr.register('0 3 * * MON-FRI', 'EducationForm::CreateDailySpoolFiles')

  mgr.register('0 3 * * *', 'DeleteOldTransactionsJob')
  # Deletes old, completed AsyncTransaction records

  mgr.register('30 3 * * 1', 'EVSS::FailedClaimsReport')
  # Notify developers about EVSS claims which could not be uploaded

  mgr.register('0 4 * * *', 'EducationForm::CreateDailyFiscalYearToDateReport')
  # Send the daily report to VA stakeholders about Education Benefits submissions
  mgr.register('5 4 * * 1-5', 'EducationForm::CreateSpoolSubmissionsReport')
  # Send the daily report to the call center about spool file submissions
  mgr.register('10 4 * * *', 'Facilities::DentalServiceReloadJob')
  # Download and cache facility access-to-care metric data
  mgr.register('25 4 * * *', 'Facilities::MentalHealthReloadJob')
  # Download and cache facility mental health phone number data
  mgr.register('35 4 * * 1-5', 'EducationForm::Create10203SpoolSubmissionsReport')
  # Send the daily 10203 report to the call center about spool file submissions
  mgr.register('45 4 * * *', 'Facilities::AccessDataDownload')
  # Download and cache facility access-to-care metric data
  mgr.register('55 4 * * *', 'Facilities::PSSGDownload')
  # Download and store drive time bands

  mgr.register('0 6 * * *', 'AccountLoginStatisticsJob')
  # Gather account login statistics for statsd

  mgr.register('0 6-18/6 * * *', 'EducationForm::Process10203Submissions')

  mgr.register('* 7 * * *', 'SignIn::DeleteExpiredSessionsJob')
  # Delete expired sessions

  mgr.register('0 12 3 * *', 'CypressViewportUpdater::UpdateCypressViewportsJob')
  # Updates Cypress files in vets-website with data from Google Analytics.
  mgr.register('0 13 * * 1', 'Mobile::V0::WeeklyMaintenanceWindowLogger')
  # Weekly logs of maintenance windows
  mgr.register('0 20 * * *', 'ClaimsApi::ClaimAuditor')
  # Daily alert of pending claims longer than acceptable threshold
  mgr.register('15 23 * * *', 'ClaimsApi::ReportUnsuccessfulSubmissions')
  # Weekly report of unsuccessful claims submissions
  mgr.register('15 23 1 * *', 'ClaimsApi::ReportMonthlySubmissions')
  # Weekly report of unsuccessful claims submissions

  mgr.register('30 2 * * *', 'Identity::UserAcceptableVerifiedCredentialTotalsJob')

  # VAForms Module
  mgr.register('0 2 * * *', 'VAForms::FormReloader')
  # Fetches latest VA forms from Drupal database and updates vets-api forms database
  mgr.register('0 2,9,16 * * 1-5', 'VAForms::FlipperStatusAlert')
  # Checks status of Flipper features expected to be enabled and alerts to Slack if any are not enabled

  mgr.register('0 16 * * *', 'VANotify::InProgressForms')
  mgr.register('0 1 * * *', 'VANotify::ClearStaleInProgressRemindersSent')
  mgr.register('0 * * * *', 'VANotify::InProgress1880Form')

  mgr.register('0 * * * *', 'CovidVaccine::ExpandedSubmissionStateJob')

  mgr.register('0 * * * *', 'PagerDuty::CacheGlobalDowntime')
  mgr.register('*/3 * * * *', 'PagerDuty::PollMaintenanceWindows')

  mgr.register('0 2 * * *', 'InProgressFormCleaner')
  mgr.register('0 */4 * * *', 'MHV::AccountStatisticsJob')
  mgr.register('0 3 * * *', 'Form1095::New1095BsJob')
  mgr.register('0 2 * * *', 'Veteran::VSOReloader')
  mgr.register('15 2 * * *', 'Preneeds::DeleteOldUploads')

  mgr.register('* * * * *', 'ExternalServicesStatusJob')
  mgr.register('* * * * *', 'ExportBreakerStatus')

  # Disable FeatureCleanerJob. https://github.com/department-of-veterans-affairs/va.gov-team/issues/53538
  # mgr.register('0 0 * * *', 'FeatureCleanerJob')
  mgr.register('0 0 * * *', 'Form1010cg::DeleteOldUploadsJob')
  mgr.register('0 1 * * *', 'TransactionalEmailAnalyticsJob')

  # VBADocuments Module
  mgr.register('45 * * * *', 'VBADocuments::UploadStatusBatch')
  # Request updated statuses for benefits intake submissions
  mgr.register('5 */2 * * *', 'VBADocuments::RunUnsuccessfulSubmissions')
  # Run VBADocuments::UploadProcessor for submissions that are stuck in uploaded status
  mgr.register('*/2 * * * *', 'VBADocuments::UploadScanner')
  # Poll upload bucket for unprocessed uploads
  mgr.register('*/2 * * * *', 'VBADocuments::UploadRemover')
  # Clean up submitted documents from S3
  mgr.register('0 0 * * 1-5', 'VBADocuments::ReportUnsuccessfulSubmissions')
  # Daily/weekly report of unsuccessful benefits intake submissions
  mgr.register('0 2 1 * *', 'VBADocuments::ReportMonthlySubmissions')
  # Monthly report of benefits intake submissions
  mgr.register('0 2,9,16 * * 1-5', 'VBADocuments::SlackNotifier')
  # Notifies slack channel if certain benefits states get stuck
  mgr.register('0 2,9,16 * * 1-5', 'VBADocuments::FlipperStatusAlert')
  # Checks status of Flipper features expected to be enabled and alerts to Slack if any are not enabled

  # Rotates Lockbox/KMS record keys and _ciphertext fields every October 12th (when the KMS key auto-rotate)
  mgr.register('0 3 * * *', 'KmsKeyRotation::BatchInitiatorJob')

  # Updates veteran representatives and organizations address attributes (including lat, long, location)
  # Updates veteran representatives email address
  mgr.register('0 3 * * *', 'RepOrgAddresses::QueueAddressUpdates')
}
# rubocop:enable Metrics/BlockLength
