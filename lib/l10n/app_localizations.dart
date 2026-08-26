import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @accountPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Contact your school administrator and provide the email or UID below.'**
  String get accountPendingBody;

  /// No description provided for @accountPendingHint.
  ///
  /// In en, this message translates to:
  /// **'This screen updates automatically after an administrator assigns your role.'**
  String get accountPendingHint;

  /// No description provided for @accountPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Your account is pending role assignment.'**
  String get accountPendingTitle;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @addBus.
  ///
  /// In en, this message translates to:
  /// **'ADD BUS'**
  String get addBus;

  /// No description provided for @addBus2.
  ///
  /// In en, this message translates to:
  /// **'Add Bus'**
  String get addBus2;

  /// No description provided for @addBusesInBusManagement.
  ///
  /// In en, this message translates to:
  /// **'Add buses in Bus Management'**
  String get addBusesInBusManagement;

  /// No description provided for @addFirstBus.
  ///
  /// In en, this message translates to:
  /// **'Add First Bus'**
  String get addFirstBus;

  /// No description provided for @addFirstStudent.
  ///
  /// In en, this message translates to:
  /// **'Add First Student'**
  String get addFirstStudent;

  /// No description provided for @addNewBus.
  ///
  /// In en, this message translates to:
  /// **'Add New Bus'**
  String get addNewBus;

  /// No description provided for @addNewStudent.
  ///
  /// In en, this message translates to:
  /// **'Add New Student'**
  String get addNewStudent;

  /// No description provided for @addNewUser.
  ///
  /// In en, this message translates to:
  /// **'Add New User'**
  String get addNewUser;

  /// No description provided for @addParent.
  ///
  /// In en, this message translates to:
  /// **'Add Parent'**
  String get addParent;

  /// No description provided for @addRoute.
  ///
  /// In en, this message translates to:
  /// **'Add route'**
  String get addRoute;

  /// No description provided for @addStudent.
  ///
  /// In en, this message translates to:
  /// **'ADD STUDENT'**
  String get addStudent;

  /// No description provided for @addStudent2.
  ///
  /// In en, this message translates to:
  /// **'Add Student'**
  String get addStudent2;

  /// No description provided for @addUser.
  ///
  /// In en, this message translates to:
  /// **'ADD USER'**
  String get addUser;

  /// No description provided for @addUser2.
  ///
  /// In en, this message translates to:
  /// **'Add User'**
  String get addUser2;

  /// No description provided for @alertSent.
  ///
  /// In en, this message translates to:
  /// **'Alert Sent'**
  String get alertSent;

  /// No description provided for @alight.
  ///
  /// In en, this message translates to:
  /// **'alight'**
  String get alight;

  /// No description provided for @allClasses.
  ///
  /// In en, this message translates to:
  /// **'All classes'**
  String get allClasses;

  /// No description provided for @allNotificationsMarkedAsRead.
  ///
  /// In en, this message translates to:
  /// **'All notifications marked as read'**
  String get allNotificationsMarkedAsRead;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'SchoolWay'**
  String get appName;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @areYouSureYouWantToDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this boarding record? This action cannot be undone.'**
  String get areYouSureYouWantToDelete;

  /// No description provided for @areYouSureYouWantToEnd.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to end this trip?'**
  String get areYouSureYouWantToEnd;

  /// No description provided for @assign.
  ///
  /// In en, this message translates to:
  /// **'ASSIGN'**
  String get assign;

  /// No description provided for @assignBus.
  ///
  /// In en, this message translates to:
  /// **'Assign Bus'**
  String get assignBus;

  /// No description provided for @assignDriver.
  ///
  /// In en, this message translates to:
  /// **'Assign Driver'**
  String get assignDriver;

  /// No description provided for @assignedBus.
  ///
  /// In en, this message translates to:
  /// **'Assigned Bus'**
  String get assignedBus;

  /// No description provided for @assignedParents.
  ///
  /// In en, this message translates to:
  /// **'Assigned Parents:'**
  String get assignedParents;

  /// No description provided for @assignedStop.
  ///
  /// In en, this message translates to:
  /// **'Assigned Stop'**
  String get assignedStop;

  /// No description provided for @attendanceByClass.
  ///
  /// In en, this message translates to:
  /// **'Attendance by class'**
  String get attendanceByClass;

  /// No description provided for @attendanceCorrectionAuditTrail.
  ///
  /// In en, this message translates to:
  /// **'Attendance Correction Audit Trail'**
  String get attendanceCorrectionAuditTrail;

  /// No description provided for @attendanceCorrections.
  ///
  /// In en, this message translates to:
  /// **'Attendance Corrections'**
  String get attendanceCorrections;

  /// No description provided for @board.
  ///
  /// In en, this message translates to:
  /// **'board'**
  String get board;

  /// No description provided for @board2.
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get board2;

  /// No description provided for @boardingAlertsBody.
  ///
  /// In en, this message translates to:
  /// **'Receive immediate notifications when your child boards or leaves the bus.'**
  String get boardingAlertsBody;

  /// No description provided for @boardingAlertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Instant boarding alerts'**
  String get boardingAlertsTitle;

  /// No description provided for @bus.
  ///
  /// In en, this message translates to:
  /// **'Bus'**
  String get bus;

  /// No description provided for @busActions.
  ///
  /// In en, this message translates to:
  /// **'Bus actions'**
  String get busActions;

  /// No description provided for @busAddedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Bus added successfully'**
  String get busAddedSuccessfully;

  /// No description provided for @busDeleted.
  ///
  /// In en, this message translates to:
  /// **'Bus deleted'**
  String get busDeleted;

  /// No description provided for @busManagement.
  ///
  /// In en, this message translates to:
  /// **'Bus Management'**
  String get busManagement;

  /// No description provided for @busNumber.
  ///
  /// In en, this message translates to:
  /// **'Bus Number *'**
  String get busNumber;

  /// No description provided for @busNumber2.
  ///
  /// In en, this message translates to:
  /// **'Bus Number'**
  String get busNumber2;

  /// No description provided for @busSimulation.
  ///
  /// In en, this message translates to:
  /// **'Bus simulation'**
  String get busSimulation;

  /// No description provided for @busStationaryFor7MinutesAnEmergency.
  ///
  /// In en, this message translates to:
  /// **'Bus stationary for 7 minutes. An emergency alert will be sent in 1 minute unless movement resumes.'**
  String get busStationaryFor7MinutesAnEmergency;

  /// No description provided for @busUpdated.
  ///
  /// In en, this message translates to:
  /// **'Bus updated'**
  String get busUpdated;

  /// No description provided for @buses.
  ///
  /// In en, this message translates to:
  /// **'Buses'**
  String get buses;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cannotEndTrip.
  ///
  /// In en, this message translates to:
  /// **'Cannot End Trip'**
  String get cannotEndTrip;

  /// No description provided for @cannotSendAlertSolutionPleaseStartA.
  ///
  /// In en, this message translates to:
  /// **'Cannot send alert. Solution: Please start a route session first from the Trip tab.'**
  String get cannotSendAlertSolutionPleaseStartA;

  /// No description provided for @capacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity *'**
  String get capacity;

  /// No description provided for @capacity2.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get capacity2;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category:'**
  String get category;

  /// No description provided for @changeBusStatus.
  ///
  /// In en, this message translates to:
  /// **'Change Bus Status'**
  String get changeBusStatus;

  /// No description provided for @changeEmail.
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get changeEmail;

  /// No description provided for @changeEmail2.
  ///
  /// In en, this message translates to:
  /// **'Change Email'**
  String get changeEmail2;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @changeStatus.
  ///
  /// In en, this message translates to:
  /// **'Change Status'**
  String get changeStatus;

  /// No description provided for @children.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get children;

  /// No description provided for @chooseAUniqueUsername.
  ///
  /// In en, this message translates to:
  /// **'Choose a unique username'**
  String get chooseAUniqueUsername;

  /// No description provided for @chooseDate.
  ///
  /// In en, this message translates to:
  /// **'Choose date'**
  String get chooseDate;

  /// No description provided for @chooseDeliveryForEachCategory.
  ///
  /// In en, this message translates to:
  /// **'Choose delivery for each category'**
  String get chooseDeliveryForEachCategory;

  /// No description provided for @schoolClass.
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get schoolClass;

  /// No description provided for @class2.
  ///
  /// In en, this message translates to:
  /// **'Class *'**
  String get class2;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @code.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get code;

  /// No description provided for @completeYourProfile.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get completeYourProfile;

  /// No description provided for @confirmNewEmail.
  ///
  /// In en, this message translates to:
  /// **'Confirm new email'**
  String get confirmNewEmail;

  /// No description provided for @confirmNewEmail2.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Email'**
  String get confirmNewEmail2;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @contactAdminToAssignStudentsToThis.
  ///
  /// In en, this message translates to:
  /// **'Contact admin to assign students to this bus'**
  String get contactAdminToAssignStudentsToThis;

  /// No description provided for @contactKindergartenAdminToAddYourChild.
  ///
  /// In en, this message translates to:
  /// **'Contact kindergarten admin to add your child'**
  String get contactKindergartenAdminToAddYourChild;

  /// No description provided for @contactSchoolAdmin.
  ///
  /// In en, this message translates to:
  /// **'Contact School Admin'**
  String get contactSchoolAdmin;

  /// No description provided for @couldNotGetYourGpsLocationCheck.
  ///
  /// In en, this message translates to:
  /// **'Could not get your GPS location. Check permission and location settings.'**
  String get couldNotGetYourGpsLocationCheck;

  /// No description provided for @couldNotGetYourGpsLocationCheck2.
  ///
  /// In en, this message translates to:
  /// **'Could not get your GPS location. Check permission and that location is on.'**
  String get couldNotGetYourGpsLocationCheck2;

  /// No description provided for @couldNotOpenThePhoneApp.
  ///
  /// In en, this message translates to:
  /// **'Could not open the phone app.'**
  String get couldNotOpenThePhoneApp;

  /// No description provided for @couldNotReadThisCardTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Could not read this card. Try again.'**
  String get couldNotReadThisCardTryAgain;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @countsOfNfcScansRecordedUnderEach.
  ///
  /// In en, this message translates to:
  /// **'Counts of NFC scans recorded under each driver account.'**
  String get countsOfNfcScansRecordedUnderEach;

  /// No description provided for @criticalDelivery.
  ///
  /// In en, this message translates to:
  /// **'Critical delivery'**
  String get criticalDelivery;

  /// No description provided for @csvManagement.
  ///
  /// In en, this message translates to:
  /// **'CSV Management'**
  String get csvManagement;

  /// No description provided for @currentEmail.
  ///
  /// In en, this message translates to:
  /// **'Current email'**
  String get currentEmail;

  /// No description provided for @currentEmail2.
  ///
  /// In en, this message translates to:
  /// **'Current Email'**
  String get currentEmail2;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @currentPassword2.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPassword2;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @delete2.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get delete2;

  /// No description provided for @deleteBus.
  ///
  /// In en, this message translates to:
  /// **'Delete Bus'**
  String get deleteBus;

  /// No description provided for @deleteBus2.
  ///
  /// In en, this message translates to:
  /// **'Delete Bus?'**
  String get deleteBus2;

  /// No description provided for @deleteRecord.
  ///
  /// In en, this message translates to:
  /// **'Delete Record'**
  String get deleteRecord;

  /// No description provided for @deleteRoute.
  ///
  /// In en, this message translates to:
  /// **'Delete route?'**
  String get deleteRoute;

  /// No description provided for @deleteStudent.
  ///
  /// In en, this message translates to:
  /// **'Delete Student'**
  String get deleteStudent;

  /// No description provided for @deleteStudent2.
  ///
  /// In en, this message translates to:
  /// **'Delete Student?'**
  String get deleteStudent2;

  /// No description provided for @deleteUser.
  ///
  /// In en, this message translates to:
  /// **'Delete User'**
  String get deleteUser;

  /// No description provided for @deleteUser2.
  ///
  /// In en, this message translates to:
  /// **'Delete User?'**
  String get deleteUser2;

  /// No description provided for @descriptionDetails.
  ///
  /// In en, this message translates to:
  /// **'Description details...'**
  String get descriptionDetails;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details *'**
  String get details;

  /// No description provided for @disable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get disable;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'DISABLED'**
  String get disabled;

  /// No description provided for @downloadErrors.
  ///
  /// In en, this message translates to:
  /// **'Download Errors'**
  String get downloadErrors;

  /// No description provided for @duplicates.
  ///
  /// In en, this message translates to:
  /// **'Duplicates'**
  String get duplicates;

  /// No description provided for @dragTheControllerToMoveTheBus.
  ///
  /// In en, this message translates to:
  /// **'Drag the controller to move the bus.'**
  String get dragTheControllerToMoveTheBus;

  /// No description provided for @driverTriggeredEmergenciesResolveActiveItemsFrom.
  ///
  /// In en, this message translates to:
  /// **'Driver-triggered emergencies. Resolve active items from Emergency alerts.'**
  String get driverTriggeredEmergenciesResolveActiveItemsFrom;

  /// No description provided for @dropOff.
  ///
  /// In en, this message translates to:
  /// **'Drop Off'**
  String get dropOff;

  /// No description provided for @durationMin.
  ///
  /// In en, this message translates to:
  /// **'Duration (min)'**
  String get durationMin;

  /// No description provided for @eGRouteA.
  ///
  /// In en, this message translates to:
  /// **'e.g. Route A'**
  String get eGRouteA;

  /// No description provided for @editBusDetails.
  ///
  /// In en, this message translates to:
  /// **'Edit Bus Details'**
  String get editBusDetails;

  /// No description provided for @editDetails.
  ///
  /// In en, this message translates to:
  /// **'Edit Details'**
  String get editDetails;

  /// No description provided for @editRecord.
  ///
  /// In en, this message translates to:
  /// **'Edit Record'**
  String get editRecord;

  /// No description provided for @editStudent.
  ///
  /// In en, this message translates to:
  /// **'Edit Student'**
  String get editStudent;

  /// No description provided for @editUserDetails.
  ///
  /// In en, this message translates to:
  /// **'Edit User Details'**
  String get editUserDetails;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @email2.
  ///
  /// In en, this message translates to:
  /// **'Email *'**
  String get email2;

  /// No description provided for @emailUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Email updated successfully.'**
  String get emailUpdatedSuccessfully;

  /// No description provided for @emergencyAlert.
  ///
  /// In en, this message translates to:
  /// **'Emergency Alert'**
  String get emergencyAlert;

  /// No description provided for @emergencyAlertHasBeenSentToKindergarten.
  ///
  /// In en, this message translates to:
  /// **'Emergency alert has been sent to kindergarten administration.'**
  String get emergencyAlertHasBeenSentToKindergarten;

  /// No description provided for @emergencyAlerts.
  ///
  /// In en, this message translates to:
  /// **'Emergency alerts'**
  String get emergencyAlerts;

  /// No description provided for @emergencyAlertsRemainAvailableDuringQuietHours.
  ///
  /// In en, this message translates to:
  /// **'Emergency alerts remain available during quiet hours.'**
  String get emergencyAlertsRemainAvailableDuringQuietHours;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @end.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get end;

  /// No description provided for @endTrip.
  ///
  /// In en, this message translates to:
  /// **'End Trip'**
  String get endTrip;

  /// No description provided for @endTripSummary.
  ///
  /// In en, this message translates to:
  /// **'End Trip Summary'**
  String get endTripSummary;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @enterARouteName.
  ///
  /// In en, this message translates to:
  /// **'Enter a route name'**
  String get enterARouteName;

  /// No description provided for @errorLoadingHistory.
  ///
  /// In en, this message translates to:
  /// **'Error loading history'**
  String get errorLoadingHistory;

  /// No description provided for @errorReportDownloadedImportingValidRows.
  ///
  /// In en, this message translates to:
  /// **'Error report downloaded. Importing valid rows...'**
  String get errorReportDownloadedImportingValidRows;

  /// No description provided for @exactLocationNotRecordedForThisScan.
  ///
  /// In en, this message translates to:
  /// **'Exact location not recorded for this scan.'**
  String get exactLocationNotRecordedForThisScan;

  /// No description provided for @exportAllZip.
  ///
  /// In en, this message translates to:
  /// **'Export All (ZIP)'**
  String get exportAllZip;

  /// No description provided for @female.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get female;

  /// No description provided for @fileContainsNoDataRows.
  ///
  /// In en, this message translates to:
  /// **'File contains no data rows.'**
  String get fileContainsNoDataRows;

  /// No description provided for @filterEvents.
  ///
  /// In en, this message translates to:
  /// **'Filter events...'**
  String get filterEvents;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get firstName;

  /// No description provided for @firstName2.
  ///
  /// In en, this message translates to:
  /// **'First Name *'**
  String get firstName2;

  /// No description provided for @fleet.
  ///
  /// In en, this message translates to:
  /// **'Fleet'**
  String get fleet;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @fromSchool.
  ///
  /// In en, this message translates to:
  /// **'From school'**
  String get fromSchool;

  /// No description provided for @gender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @gpsTrackingDisabled.
  ///
  /// In en, this message translates to:
  /// **'GPS Tracking Disabled'**
  String get gpsTrackingDisabled;

  /// No description provided for @gpsWasNotRecordedForThisScan.
  ///
  /// In en, this message translates to:
  /// **'GPS was not recorded for this scan. The line shows the planned route.'**
  String get gpsWasNotRecordedForThisScan;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @holdStudentCardNearDeviceToScan.
  ///
  /// In en, this message translates to:
  /// **'Hold student card near device to scan'**
  String get holdStudentCardNearDeviceToScan;

  /// No description provided for @holdTheCardNearTheDeviceClose.
  ///
  /// In en, this message translates to:
  /// **'Hold the card near the device. Close this panel and use Manual if NFC is unavailable.'**
  String get holdTheCardNearTheDeviceClose;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'INACTIVE'**
  String get inactive;

  /// No description provided for @incidentDisruptionLog.
  ///
  /// In en, this message translates to:
  /// **'Incident & Disruption Log'**
  String get incidentDisruptionLog;

  /// No description provided for @incidentReportLoggedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Incident report logged successfully.'**
  String get incidentReportLoggedSuccessfully;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get lastName;

  /// No description provided for @lastName2.
  ///
  /// In en, this message translates to:
  /// **'Last Name *'**
  String get lastName2;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get live;

  /// No description provided for @liveMap.
  ///
  /// In en, this message translates to:
  /// **'Live Map'**
  String get liveMap;

  /// No description provided for @livePosition.
  ///
  /// In en, this message translates to:
  /// **'Live position'**
  String get livePosition;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @locationPermissionIsRequiredToShowYour.
  ///
  /// In en, this message translates to:
  /// **'Location permission is required to show your position on the map.'**
  String get locationPermissionIsRequiredToShowYour;

  /// No description provided for @locationUnavailableAlertUsedAFallbackArea.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable — alert used a fallback area. Enable location for precise coordinates.'**
  String get locationUnavailableAlertUsedAFallbackArea;

  /// No description provided for @logIncidentDisruption.
  ///
  /// In en, this message translates to:
  /// **'Log Incident / Disruption'**
  String get logIncidentDisruption;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @male.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get male;

  /// No description provided for @maintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get maintenance;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @manageBusesUsersAndStudents.
  ///
  /// In en, this message translates to:
  /// **'Manage buses, users, and students'**
  String get manageBusesUsersAndStudents;

  /// No description provided for @manageParents.
  ///
  /// In en, this message translates to:
  /// **'Manage Parents'**
  String get manageParents;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @manualOverride.
  ///
  /// In en, this message translates to:
  /// **'Manual Override'**
  String get manualOverride;

  /// No description provided for @map.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get map;

  /// No description provided for @mapPinsAndRouteOrderFollowYour.
  ///
  /// In en, this message translates to:
  /// **'Map pins and route order follow your choice.'**
  String get mapPinsAndRouteOrderFollowYour;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @markedResolved.
  ///
  /// In en, this message translates to:
  /// **'Marked resolved'**
  String get markedResolved;

  /// No description provided for @med.
  ///
  /// In en, this message translates to:
  /// **'Med'**
  String get med;

  /// No description provided for @motion.
  ///
  /// In en, this message translates to:
  /// **'Motion'**
  String get motion;

  /// No description provided for @motionFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get motionFull;

  /// No description provided for @motionReduced.
  ///
  /// In en, this message translates to:
  /// **'Reduced'**
  String get motionReduced;

  /// No description provided for @motionSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get motionSystem;

  /// No description provided for @muteRoutineAlerts.
  ///
  /// In en, this message translates to:
  /// **'Mute routine alerts'**
  String get muteRoutineAlerts;

  /// No description provided for @myChildren.
  ///
  /// In en, this message translates to:
  /// **'My Children'**
  String get myChildren;

  /// No description provided for @myLocation.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get myLocation;

  /// No description provided for @needAnAccountPleaseContactAdmin.
  ///
  /// In en, this message translates to:
  /// **'Need an account? Please contact admin.'**
  String get needAnAccountPleaseContactAdmin;

  /// No description provided for @newEmail.
  ///
  /// In en, this message translates to:
  /// **'New email'**
  String get newEmail;

  /// No description provided for @newEmail2.
  ///
  /// In en, this message translates to:
  /// **'New Email'**
  String get newEmail2;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @newPasswordMustBeAtLeast6.
  ///
  /// In en, this message translates to:
  /// **'New password must be at least 6 characters'**
  String get newPasswordMustBeAtLeast6;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @nfc.
  ///
  /// In en, this message translates to:
  /// **'NFC'**
  String get nfc;

  /// No description provided for @nfcBoardAndDropOffCountsPer.
  ///
  /// In en, this message translates to:
  /// **'NFC board and drop off counts per bus. Use the calendar to move the 7-day window.'**
  String get nfcBoardAndDropOffCountsPer;

  /// No description provided for @nfcCardId.
  ///
  /// In en, this message translates to:
  /// **'NFC Card ID'**
  String get nfcCardId;

  /// No description provided for @nfcCardId2.
  ///
  /// In en, this message translates to:
  /// **'NFC Card ID *'**
  String get nfcCardId2;

  /// No description provided for @nfcIsOnlyAvailableOnMobileDevices.
  ///
  /// In en, this message translates to:
  /// **'NFC is only available on Mobile devices. On web, use manual record.'**
  String get nfcIsOnlyAvailableOnMobileDevices;

  /// No description provided for @nfcScanningDisabled.
  ///
  /// In en, this message translates to:
  /// **'NFC Scanning Disabled'**
  String get nfcScanningDisabled;

  /// No description provided for @nfcTagUpdated.
  ///
  /// In en, this message translates to:
  /// **'NFC tag updated'**
  String get nfcTagUpdated;

  /// No description provided for @noActiveEmergencyAlerts.
  ///
  /// In en, this message translates to:
  /// **'No active emergency alerts.'**
  String get noActiveEmergencyAlerts;

  /// No description provided for @noAttendanceCorrectionsLogged.
  ///
  /// In en, this message translates to:
  /// **'No attendance corrections logged.'**
  String get noAttendanceCorrectionsLogged;

  /// No description provided for @noBoardingEventsFoundForThisDate.
  ///
  /// In en, this message translates to:
  /// **'No boarding events found for this date.'**
  String get noBoardingEventsFoundForThisDate;

  /// No description provided for @noBoardingRecordsYet.
  ///
  /// In en, this message translates to:
  /// **'No boarding records yet'**
  String get noBoardingRecordsYet;

  /// No description provided for @noBusActionsRecordedOnThisDate.
  ///
  /// In en, this message translates to:
  /// **'No bus actions recorded on this date.'**
  String get noBusActionsRecordedOnThisDate;

  /// No description provided for @noBusAssignedYet.
  ///
  /// In en, this message translates to:
  /// **'No bus assigned yet'**
  String get noBusAssignedYet;

  /// No description provided for @noBusUnassign.
  ///
  /// In en, this message translates to:
  /// **'No bus (unassign)'**
  String get noBusUnassign;

  /// No description provided for @noBusesInFleet.
  ///
  /// In en, this message translates to:
  /// **'No buses in fleet'**
  String get noBusesInFleet;

  /// No description provided for @noBusesRegistered.
  ///
  /// In en, this message translates to:
  /// **'No buses registered.'**
  String get noBusesRegistered;

  /// No description provided for @noBusesYet.
  ///
  /// In en, this message translates to:
  /// **'No buses yet'**
  String get noBusesYet;

  /// No description provided for @noChildrenAssignedYetContactKindergartenAdmin.
  ///
  /// In en, this message translates to:
  /// **'No children assigned yet.\nContact kindergarten admin to add your child.'**
  String get noChildrenAssignedYetContactKindergartenAdmin;

  /// No description provided for @noChildrenFoundForTripHistory.
  ///
  /// In en, this message translates to:
  /// **'No children found for trip history'**
  String get noChildrenFoundForTripHistory;

  /// No description provided for @noCompletedRoutesFound.
  ///
  /// In en, this message translates to:
  /// **'No completed routes found.'**
  String get noCompletedRoutesFound;

  /// No description provided for @noDriver.
  ///
  /// In en, this message translates to:
  /// **'No driver'**
  String get noDriver;

  /// No description provided for @noDriverAssigned.
  ///
  /// In en, this message translates to:
  /// **'No driver assigned'**
  String get noDriverAssigned;

  /// No description provided for @noDriverAttributedScansInThisPeriod.
  ///
  /// In en, this message translates to:
  /// **'No driver-attributed scans in this period.'**
  String get noDriverAttributedScansInThisPeriod;

  /// No description provided for @noEmergencyAlertsRecorded.
  ///
  /// In en, this message translates to:
  /// **'No emergency alerts recorded.'**
  String get noEmergencyAlertsRecorded;

  /// No description provided for @noGpsDataAvailableForThisSession.
  ///
  /// In en, this message translates to:
  /// **'No GPS data available for this session.'**
  String get noGpsDataAvailableForThisSession;

  /// No description provided for @noNotificationsYetYouLlSeeAlerts.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet.\nYou’ll see alerts when your child boards or leaves the bus.'**
  String get noNotificationsYetYouLlSeeAlerts;

  /// No description provided for @noOperationalIncidentReportsFound.
  ///
  /// In en, this message translates to:
  /// **'No operational incident reports found.'**
  String get noOperationalIncidentReportsFound;

  /// No description provided for @noParentSelected.
  ///
  /// In en, this message translates to:
  /// **'No parent selected'**
  String get noParentSelected;

  /// No description provided for @noPlannedRouteIsAssignedToThis.
  ///
  /// In en, this message translates to:
  /// **'No planned route is assigned to this bus, and this scan has no GPS position. Nothing to show on the map yet.'**
  String get noPlannedRouteIsAssignedToThis;

  /// No description provided for @noPlannedRoutesYet.
  ///
  /// In en, this message translates to:
  /// **'No planned routes yet'**
  String get noPlannedRoutesYet;

  /// No description provided for @noRecentIncidents.
  ///
  /// In en, this message translates to:
  /// **'No recent incidents.'**
  String get noRecentIncidents;

  /// No description provided for @noRouteHistoryCoordinatesRecordedForThis.
  ///
  /// In en, this message translates to:
  /// **'No route history coordinates recorded for this trip.'**
  String get noRouteHistoryCoordinatesRecordedForThis;

  /// No description provided for @noRouteAssigned.
  ///
  /// In en, this message translates to:
  /// **'No Route Assigned'**
  String get noRouteAssigned;

  /// No description provided for @noRouteAssignedBody.
  ///
  /// In en, this message translates to:
  /// **'Bus \"{busNumber}\" does not have a route assigned.\nPlease ask your school administrator to assign a route to this bus in the admin dashboard.'**
  String noRouteAssignedBody(String busNumber);

  /// No description provided for @routeRequiredForTrips.
  ///
  /// In en, this message translates to:
  /// **'Required for drivers to start trips'**
  String get routeRequiredForTrips;

  /// No description provided for @quickSetup.
  ///
  /// In en, this message translates to:
  /// **'Quick Setup'**
  String get quickSetup;

  /// No description provided for @quickSetupDescription.
  ///
  /// In en, this message translates to:
  /// **'Register a new student with parent, stop point, and bus in one flow.'**
  String get quickSetupDescription;

  /// No description provided for @quickSetupDone.
  ///
  /// In en, this message translates to:
  /// **'Student registered successfully'**
  String get quickSetupDone;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String stepOf(int current, int total);

  /// No description provided for @useExistingParent.
  ///
  /// In en, this message translates to:
  /// **'Existing parent'**
  String get useExistingParent;

  /// No description provided for @createNewParent.
  ///
  /// In en, this message translates to:
  /// **'New parent'**
  String get createNewParent;

  /// No description provided for @selectRouteFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a route first to see its buses'**
  String get selectRouteFirst;

  /// No description provided for @busesOnSelectedRoute.
  ///
  /// In en, this message translates to:
  /// **'{count} bus(es) on this route'**
  String busesOnSelectedRoute(int count);

  /// No description provided for @noSavedRoutesCreateOneInRoute.
  ///
  /// In en, this message translates to:
  /// **'No saved routes. Create one in Route planner first.'**
  String get noSavedRoutesCreateOneInRoute;

  /// No description provided for @noSavedRoutesYetOpenRoutePlanner.
  ///
  /// In en, this message translates to:
  /// **'No saved routes yet. Open Route planner from the admin toolbar and save a route first.'**
  String get noSavedRoutesYetOpenRoutePlanner;

  /// No description provided for @noScansYetTapAnNfcCard.
  ///
  /// In en, this message translates to:
  /// **'No scans yet — tap an NFC card to begin'**
  String get noScansYetTapAnNfcCard;

  /// No description provided for @noStudentOnThisBusMatchesThis.
  ///
  /// In en, this message translates to:
  /// **'No student on this bus matches this card.'**
  String get noStudentOnThisBusMatchesThis;

  /// No description provided for @noStudentsAssigned.
  ///
  /// In en, this message translates to:
  /// **'No students assigned'**
  String get noStudentsAssigned;

  /// No description provided for @noStudentsFound.
  ///
  /// In en, this message translates to:
  /// **'No students found'**
  String get noStudentsFound;

  /// No description provided for @noStudentsInThisClass.
  ///
  /// In en, this message translates to:
  /// **'No students in this class'**
  String get noStudentsInThisClass;

  /// No description provided for @noStudentsYet.
  ///
  /// In en, this message translates to:
  /// **'No students yet'**
  String get noStudentsYet;

  /// No description provided for @noTripHistory.
  ///
  /// In en, this message translates to:
  /// **'No Trip History'**
  String get noTripHistory;

  /// No description provided for @noUser.
  ///
  /// In en, this message translates to:
  /// **'No user'**
  String get noUser;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get noUsersFound;

  /// No description provided for @notificationPreferences.
  ///
  /// In en, this message translates to:
  /// **'Notification Preferences'**
  String get notificationPreferences;

  /// No description provided for @notificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification settings'**
  String get notificationSettings;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @trafficEtaRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing traffic ETA…'**
  String get trafficEtaRefreshing;

  /// No description provided for @trafficEtaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Traffic ETA unavailable'**
  String get trafficEtaUnavailable;

  /// No description provided for @trafficEtaUpdatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Traffic ETA updated'**
  String get trafficEtaUpdatedLabel;

  /// No description provided for @onTimePerformance.
  ///
  /// In en, this message translates to:
  /// **'On-Time Performance'**
  String get onTimePerformance;

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in maps'**
  String get openInMaps;

  /// No description provided for @openInSchoolwayMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in SchoolWay Maps'**
  String get openInSchoolwayMaps;

  /// No description provided for @operationalOverview.
  ///
  /// In en, this message translates to:
  /// **'Operational Overview'**
  String get operationalOverview;

  /// No description provided for @operationalReportsForAttendanceBusesAndSafety.
  ///
  /// In en, this message translates to:
  /// **'Operational reports for attendance, buses, and safety'**
  String get operationalReportsForAttendanceBusesAndSafety;

  /// No description provided for @operationsManagement.
  ///
  /// In en, this message translates to:
  /// **'Operations Management'**
  String get operationsManagement;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @parentContactHiddenForPrivacyReachOut.
  ///
  /// In en, this message translates to:
  /// **'Parent contact hidden for privacy. Reach out to school admin for assistance.'**
  String get parentContactHiddenForPrivacyReachOut;

  /// No description provided for @parentsNotified.
  ///
  /// In en, this message translates to:
  /// **'Parents notified'**
  String get parentsNotified;

  /// No description provided for @parentsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Parents updated'**
  String get parentsUpdated;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordMustBeAtLeast6Characters.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordMustBeAtLeast6Characters;

  /// No description provided for @passwordResetEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset email sent.'**
  String get passwordResetEmailSent;

  /// No description provided for @passwordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Password updated'**
  String get passwordUpdated;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumber;

  /// No description provided for @phoneNumber2.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber2;

  /// No description provided for @plannedPath.
  ///
  /// In en, this message translates to:
  /// **'Planned path'**
  String get plannedPath;

  /// No description provided for @plannedRoute.
  ///
  /// In en, this message translates to:
  /// **'Planned route *'**
  String get plannedRoute;

  /// No description provided for @plannedRoute2.
  ///
  /// In en, this message translates to:
  /// **'Planned Route'**
  String get plannedRoute2;

  /// No description provided for @plannedRoute3.
  ///
  /// In en, this message translates to:
  /// **'Planned Route *'**
  String get plannedRoute3;

  /// No description provided for @plannedStop.
  ///
  /// In en, this message translates to:
  /// **'Planned Stop'**
  String get plannedStop;

  /// No description provided for @plannedStop2.
  ///
  /// In en, this message translates to:
  /// **'Planned Stop *'**
  String get plannedStop2;

  /// No description provided for @plateNumber.
  ///
  /// In en, this message translates to:
  /// **'Plate Number *'**
  String get plateNumber;

  /// No description provided for @plateNumber2.
  ///
  /// In en, this message translates to:
  /// **'Plate Number'**
  String get plateNumber2;

  /// No description provided for @pleaseFillAllFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill all fields'**
  String get pleaseFillAllFields;

  /// No description provided for @pleaseFillAllRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill all required fields'**
  String get pleaseFillAllRequiredFields;

  /// No description provided for @pleaseFillRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill required fields'**
  String get pleaseFillRequiredFields;

  /// No description provided for @pleaseFillRequiredFieldsIncludingRouteAnd.
  ///
  /// In en, this message translates to:
  /// **'Please fill required fields, including route and stop'**
  String get pleaseFillRequiredFieldsIncludingRouteAnd;

  /// No description provided for @pleaseSignIn.
  ///
  /// In en, this message translates to:
  /// **'Please sign in'**
  String get pleaseSignIn;

  /// No description provided for @pleaseTapNfcCard.
  ///
  /// In en, this message translates to:
  /// **'Please tap NFC card...'**
  String get pleaseTapNfcCard;

  /// No description provided for @quickOverview.
  ///
  /// In en, this message translates to:
  /// **'Quick Overview'**
  String get quickOverview;

  /// No description provided for @quickStats.
  ///
  /// In en, this message translates to:
  /// **'Quick Stats'**
  String get quickStats;

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason *'**
  String get reason;

  /// No description provided for @rebuild.
  ///
  /// In en, this message translates to:
  /// **'Rebuild'**
  String get rebuild;

  /// No description provided for @rebuildRouteGeometryWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Rebuild Route Geometry (Google Maps)'**
  String get rebuildRouteGeometryWithGoogle;

  /// No description provided for @rebuildExistingRoutes.
  ///
  /// In en, this message translates to:
  /// **'Rebuild Existing Routes?'**
  String get rebuildExistingRoutes;

  /// No description provided for @receiveSchoolwayNotifications.
  ///
  /// In en, this message translates to:
  /// **'Receive SchoolWay notifications'**
  String get receiveSchoolwayNotifications;

  /// No description provided for @recentIncidents.
  ///
  /// In en, this message translates to:
  /// **'Recent Incidents'**
  String get recentIncidents;

  /// No description provided for @recentScans.
  ///
  /// In en, this message translates to:
  /// **'Recent Scans'**
  String get recentScans;

  /// No description provided for @recordDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Record deleted successfully.'**
  String get recordDeletedSuccessfully;

  /// No description provided for @recordUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Record updated successfully.'**
  String get recordUpdatedSuccessfully;

  /// No description provided for @reportDate.
  ///
  /// In en, this message translates to:
  /// **'Report Date'**
  String get reportDate;

  /// No description provided for @reportIncidentDelay.
  ///
  /// In en, this message translates to:
  /// **'Report Incident / Delay'**
  String get reportIncidentDelay;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @reportsAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Reports & Analytics'**
  String get reportsAnalytics;

  /// No description provided for @resetEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Reset email sent'**
  String get resetEmailSent;

  /// No description provided for @resolve.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get resolve;

  /// No description provided for @resumedYourActiveRouteSession.
  ///
  /// In en, this message translates to:
  /// **'Resumed your active route session.'**
  String get resumedYourActiveRouteSession;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @role2.
  ///
  /// In en, this message translates to:
  /// **'Role *'**
  String get role2;

  /// No description provided for @routeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Route deleted'**
  String get routeDeleted;

  /// No description provided for @routeHistory.
  ///
  /// In en, this message translates to:
  /// **'Route History'**
  String get routeHistory;

  /// No description provided for @routeName.
  ///
  /// In en, this message translates to:
  /// **'Route name'**
  String get routeName;

  /// No description provided for @routePlannerTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap map: pins 1 → 2 → 3... Google follows drivable roads.'**
  String get routePlannerTapHint;

  /// No description provided for @routeSessionEndedDataSynced.
  ///
  /// In en, this message translates to:
  /// **'Route session ended. Data synced.'**
  String get routeSessionEndedDataSynced;

  /// No description provided for @routeSessionStartedFromActiveBusAssignment.
  ///
  /// In en, this message translates to:
  /// **'Route session started from active bus assignment.'**
  String get routeSessionStartedFromActiveBusAssignment;

  /// No description provided for @routeSessionStartedReadyToScanNfc.
  ///
  /// In en, this message translates to:
  /// **'Route session started. Ready to scan NFC cards.'**
  String get routeSessionStartedReadyToScanNfc;

  /// No description provided for @rowDiagnosticDetails.
  ///
  /// In en, this message translates to:
  /// **'Row Diagnostic Details:'**
  String get rowDiagnosticDetails;

  /// No description provided for @safetyBody.
  ///
  /// In en, this message translates to:
  /// **'A unified, secure platform for parents, drivers, and school staff.'**
  String get safetyBody;

  /// No description provided for @safetyTitle.
  ///
  /// In en, this message translates to:
  /// **'All-in-one safety'**
  String get safetyTitle;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @save2.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get save2;

  /// No description provided for @saveAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Save and continue'**
  String get saveAndContinue;

  /// No description provided for @saveEvent.
  ///
  /// In en, this message translates to:
  /// **'Save Event'**
  String get saveEvent;

  /// No description provided for @scan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scan;

  /// No description provided for @scanNfc.
  ///
  /// In en, this message translates to:
  /// **'Scan NFC'**
  String get scanNfc;

  /// No description provided for @scanNfcTag.
  ///
  /// In en, this message translates to:
  /// **'Scan NFC Tag'**
  String get scanNfcTag;

  /// No description provided for @scanOnMap.
  ///
  /// In en, this message translates to:
  /// **'Scan on map'**
  String get scanOnMap;

  /// No description provided for @searchAuditLogsExceptions.
  ///
  /// In en, this message translates to:
  /// **'Search audit logs & exceptions...'**
  String get searchAuditLogsExceptions;

  /// No description provided for @searchBuses.
  ///
  /// In en, this message translates to:
  /// **'Search buses...'**
  String get searchBuses;

  /// No description provided for @searchByNameOrEmail.
  ///
  /// In en, this message translates to:
  /// **'Search by name or email...'**
  String get searchByNameOrEmail;

  /// No description provided for @searchStudents.
  ///
  /// In en, this message translates to:
  /// **'Search students...'**
  String get searchStudents;

  /// No description provided for @selectABusToStart.
  ///
  /// In en, this message translates to:
  /// **'Select a bus to start'**
  String get selectABusToStart;

  /// No description provided for @selectAPlannedRouteForThisBus.
  ///
  /// In en, this message translates to:
  /// **'Select a planned route for this bus'**
  String get selectAPlannedRouteForThisBus;

  /// No description provided for @selectAssignedBus.
  ///
  /// In en, this message translates to:
  /// **'Select assigned bus'**
  String get selectAssignedBus;

  /// No description provided for @selectDriver.
  ///
  /// In en, this message translates to:
  /// **'Select Driver'**
  String get selectDriver;

  /// No description provided for @selectGender.
  ///
  /// In en, this message translates to:
  /// **'Select gender'**
  String get selectGender;

  /// No description provided for @selectMultiple.
  ///
  /// In en, this message translates to:
  /// **'Select multiple'**
  String get selectMultiple;

  /// No description provided for @selectNewEventType.
  ///
  /// In en, this message translates to:
  /// **'Select new event type:'**
  String get selectNewEventType;

  /// No description provided for @selectParent.
  ///
  /// In en, this message translates to:
  /// **'Select Parent'**
  String get selectParent;

  /// No description provided for @selectedRouteNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'Selected route no longer exists'**
  String get selectedRouteNoLongerExists;

  /// No description provided for @sendAlert.
  ///
  /// In en, this message translates to:
  /// **'SEND ALERT'**
  String get sendAlert;

  /// No description provided for @sendEmergencyAlertToKindergartenAdministration.
  ///
  /// In en, this message translates to:
  /// **'Send emergency alert to kindergarten administration?'**
  String get sendEmergencyAlertToKindergartenAdministration;

  /// No description provided for @setActive.
  ///
  /// In en, this message translates to:
  /// **'Set Active'**
  String get setActive;

  /// No description provided for @setIdle.
  ///
  /// In en, this message translates to:
  /// **'Set Idle'**
  String get setIdle;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @severity.
  ///
  /// In en, this message translates to:
  /// **'Severity:'**
  String get severity;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @simulatedPosition.
  ///
  /// In en, this message translates to:
  /// **'Simulated position'**
  String get simulatedPosition;

  /// No description provided for @simulationActive.
  ///
  /// In en, this message translates to:
  /// **'Simulation active'**
  String get simulationActive;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @startARouteSessionFromTheTrip.
  ///
  /// In en, this message translates to:
  /// **'Start a route session from the Trip tab\nto enable NFC card scanning'**
  String get startARouteSessionFromTheTrip;

  /// No description provided for @startARouteSessionToShareLive.
  ///
  /// In en, this message translates to:
  /// **'Start a route session to share live location with parents'**
  String get startARouteSessionToShareLive;

  /// No description provided for @startARouteSessionToViewAnd.
  ///
  /// In en, this message translates to:
  /// **'Start a route session to view\nand manage student boarding'**
  String get startARouteSessionToViewAnd;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @statusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Status updated'**
  String get statusUpdated;

  /// No description provided for @stops.
  ///
  /// In en, this message translates to:
  /// **'Stops'**
  String get stops;

  /// No description provided for @studentActions.
  ///
  /// In en, this message translates to:
  /// **'Student actions'**
  String get studentActions;

  /// No description provided for @studentAddedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Student added successfully'**
  String get studentAddedSuccessfully;

  /// No description provided for @studentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Student deleted'**
  String get studentDeleted;

  /// No description provided for @studentId.
  ///
  /// In en, this message translates to:
  /// **'Student ID *'**
  String get studentId;

  /// No description provided for @studentListUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Student List Unavailable'**
  String get studentListUnavailable;

  /// No description provided for @studentManagement.
  ///
  /// In en, this message translates to:
  /// **'Student Management'**
  String get studentManagement;

  /// No description provided for @studentUpdated.
  ///
  /// In en, this message translates to:
  /// **'Student updated'**
  String get studentUpdated;

  /// No description provided for @students.
  ///
  /// In en, this message translates to:
  /// **'Students'**
  String get students;

  /// No description provided for @submitReport.
  ///
  /// In en, this message translates to:
  /// **'Submit Report'**
  String get submitReport;

  /// No description provided for @tapABusCardToShowIt.
  ///
  /// In en, this message translates to:
  /// **'Tap a bus card to show it on the map'**
  String get tapABusCardToShowIt;

  /// No description provided for @tapAClassToExpandTheRoster.
  ///
  /// In en, this message translates to:
  /// **'Tap a class to expand the roster. Tap a student for action times.'**
  String get tapAClassToExpandTheRoster;

  /// No description provided for @tapInTheTopCornerToDraw.
  ///
  /// In en, this message translates to:
  /// **'Tap + in the top corner to draw a route on the map.'**
  String get tapInTheTopCornerToDraw;

  /// No description provided for @tapNfcCard.
  ///
  /// In en, this message translates to:
  /// **'TAP NFC CARD'**
  String get tapNfcCard;

  /// No description provided for @tapTheMapToAddAtLeast.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to add at least one stop'**
  String get tapTheMapToAddAtLeast;

  /// No description provided for @temporaryPassword.
  ///
  /// In en, this message translates to:
  /// **'Temporary Password *'**
  String get temporaryPassword;

  /// No description provided for @text45.
  ///
  /// In en, this message translates to:
  /// **'45'**
  String get text45;

  /// No description provided for @text60.
  ///
  /// In en, this message translates to:
  /// **'+60'**
  String get text60;

  /// No description provided for @text65.
  ///
  /// In en, this message translates to:
  /// **'+65'**
  String get text65;

  /// No description provided for @thatPlannedRouteNoLongerExistsRefresh.
  ///
  /// In en, this message translates to:
  /// **'That planned route no longer exists. Refresh and try again.'**
  String get thatPlannedRouteNoLongerExistsRefresh;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @thisActionCannotBeUndoneAreYou.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone. Are you sure?'**
  String get thisActionCannotBeUndoneAreYou;

  /// No description provided for @thisReplacesLiveGpsAndIsVisible.
  ///
  /// In en, this message translates to:
  /// **'This replaces live GPS and is visible to parents and admins.'**
  String get thisReplacesLiveGpsAndIsVisible;

  /// No description provided for @thisWillRecalculateAndOverwriteSavedRoute.
  ///
  /// In en, this message translates to:
  /// **'This will recalculate and overwrite saved route waypoints using Google Maps drive routes for all planned routes. Stops remain unchanged.'**
  String get thisWillRecalculateAndOverwriteSavedRoute;

  /// No description provided for @toSchool.
  ///
  /// In en, this message translates to:
  /// **'To school'**
  String get toSchool;

  /// No description provided for @todaySBus.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Bus'**
  String get todaySBus;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @valid.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get valid;

  /// No description provided for @invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid'**
  String get invalid;

  /// No description provided for @existingInDatabase.
  ///
  /// In en, this message translates to:
  /// **'Existing in DB'**
  String get existingInDatabase;

  /// No description provided for @csvRecordsTotal.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 record total} other{{count} records total}}'**
  String csvRecordsTotal(int count);

  /// No description provided for @trip.
  ///
  /// In en, this message translates to:
  /// **'Trip'**
  String get trip;

  /// No description provided for @tripDirection.
  ///
  /// In en, this message translates to:
  /// **'Trip direction'**
  String get tripDirection;

  /// No description provided for @tripHistory.
  ///
  /// In en, this message translates to:
  /// **'Trip History'**
  String get tripHistory;

  /// No description provided for @turnOffToStopAllNewPush.
  ///
  /// In en, this message translates to:
  /// **'Turn off to stop all new push and inbox notifications.'**
  String get turnOffToStopAllNewPush;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @unknownReportType.
  ///
  /// In en, this message translates to:
  /// **'Unknown report type'**
  String get unknownReportType;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'UPDATE'**
  String get update;

  /// No description provided for @updateNfcTag.
  ///
  /// In en, this message translates to:
  /// **'Update NFC Tag'**
  String get updateNfcTag;

  /// No description provided for @updateNfcTagId.
  ///
  /// In en, this message translates to:
  /// **'Update NFC Tag ID'**
  String get updateNfcTagId;

  /// No description provided for @updateProfile.
  ///
  /// In en, this message translates to:
  /// **'Update Profile'**
  String get updateProfile;

  /// No description provided for @updatingRoute.
  ///
  /// In en, this message translates to:
  /// **'Updating routeâ€¦'**
  String get updatingRoute;

  /// No description provided for @userActions.
  ///
  /// In en, this message translates to:
  /// **'User actions'**
  String get userActions;

  /// No description provided for @userDeleted.
  ///
  /// In en, this message translates to:
  /// **'User deleted'**
  String get userDeleted;

  /// No description provided for @userDetails.
  ///
  /// In en, this message translates to:
  /// **'User Details'**
  String get userDetails;

  /// No description provided for @userManagement.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get userManagement;

  /// No description provided for @userProfileNotFound.
  ///
  /// In en, this message translates to:
  /// **'User profile not found'**
  String get userProfileNotFound;

  /// No description provided for @userUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'User updated successfully'**
  String get userUpdatedSuccessfully;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username *'**
  String get username;

  /// No description provided for @username2.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username2;

  /// No description provided for @usernameCannotContainSpaces.
  ///
  /// In en, this message translates to:
  /// **'Username cannot contain spaces'**
  String get usernameCannotContainSpaces;

  /// No description provided for @users.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get users;

  /// No description provided for @validGpsPathDataNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Valid GPS path data not available.'**
  String get validGpsPathDataNotAvailable;

  /// No description provided for @viewOnboardingAgain.
  ///
  /// In en, this message translates to:
  /// **'View onboarding again'**
  String get viewOnboardingAgain;

  /// No description provided for @viewRouteHistory.
  ///
  /// In en, this message translates to:
  /// **'View route history'**
  String get viewRouteHistory;

  /// No description provided for @weNeedAFewMoreDetailsTo.
  ///
  /// In en, this message translates to:
  /// **'We need a few more details to continue.'**
  String get weNeedAFewMoreDetailsTo;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcome;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Track your child\'s kindergarten bus in real time. No more guessing, just peace of mind.'**
  String get welcomeBody;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to SchoolWay'**
  String get welcomeTitle;

  /// No description provided for @youCanChooseAnyBusAssignedTo.
  ///
  /// In en, this message translates to:
  /// **'You can choose any bus assigned to you before starting.'**
  String get youCanChooseAnyBusAssignedTo;

  /// No description provided for @youCannotDeleteYourOwnAccount.
  ///
  /// In en, this message translates to:
  /// **'You cannot delete your own account'**
  String get youCannotDeleteYourOwnAccount;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// No description provided for @diagnosticsDescription.
  ///
  /// In en, this message translates to:
  /// **'Private diagnostic history stays on this device until you share it.'**
  String get diagnosticsDescription;

  /// No description provided for @shareDiagnosticLog.
  ///
  /// In en, this message translates to:
  /// **'Share diagnostic log'**
  String get shareDiagnosticLog;

  /// No description provided for @saveDiagnosticLog.
  ///
  /// In en, this message translates to:
  /// **'Save diagnostic log'**
  String get saveDiagnosticLog;

  /// No description provided for @copyIncidentReference.
  ///
  /// In en, this message translates to:
  /// **'Copy latest incident reference'**
  String get copyIncidentReference;

  /// No description provided for @clearDiagnosticHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear diagnostic history'**
  String get clearDiagnosticHistory;

  /// No description provided for @clearDiagnosticHistoryConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete all diagnostic history stored on this device?'**
  String get clearDiagnosticHistoryConfirmation;

  /// No description provided for @diagnosticHistoryCleared.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic history cleared.'**
  String get diagnosticHistoryCleared;

  /// No description provided for @diagnosticLogReady.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic log is ready to share.'**
  String get diagnosticLogReady;

  /// No description provided for @diagnosticLogDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic log downloaded.'**
  String get diagnosticLogDownloaded;

  /// No description provided for @noDiagnosticEvents.
  ///
  /// In en, this message translates to:
  /// **'No diagnostic events recorded.'**
  String get noDiagnosticEvents;

  /// No description provided for @noIncidentReference.
  ///
  /// In en, this message translates to:
  /// **'No incident reference is available.'**
  String get noIncidentReference;

  /// No description provided for @incidentReferenceCopied.
  ///
  /// In en, this message translates to:
  /// **'Incident reference copied.'**
  String get incidentReferenceCopied;

  /// No description provided for @diagnosticEventCount.
  ///
  /// In en, this message translates to:
  /// **'{count} events • {size}'**
  String diagnosticEventCount(int count, String size);

  /// No description provided for @diagnosticRange.
  ///
  /// In en, this message translates to:
  /// **'From {oldest} to {newest}'**
  String diagnosticRange(String oldest, String newest);

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get somethingWentWrong;

  /// No description provided for @errorReference.
  ///
  /// In en, this message translates to:
  /// **'Reference: {incidentId}'**
  String errorReference(String incidentId);

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @openDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Open diagnostics'**
  String get openDiagnostics;

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'SchoolWay could not finish starting.'**
  String get startupFailed;

  /// No description provided for @authenticationError.
  ///
  /// In en, this message translates to:
  /// **'Please check your sign-in details and try again.'**
  String get authenticationError;

  /// No description provided for @authorizationError.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to perform this action.'**
  String get authorizationError;

  /// No description provided for @validationError.
  ///
  /// In en, this message translates to:
  /// **'Please check the information you entered.'**
  String get validationError;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Check your internet connection and try again.'**
  String get networkError;

  /// No description provided for @timeoutError.
  ///
  /// In en, this message translates to:
  /// **'The request timed out. Please try again.'**
  String get timeoutError;

  /// No description provided for @unavailableError.
  ///
  /// In en, this message translates to:
  /// **'The service is temporarily unavailable. Please try again.'**
  String get unavailableError;

  /// No description provided for @storageError.
  ///
  /// In en, this message translates to:
  /// **'The device could not save the requested data.'**
  String get storageError;

  /// No description provided for @locationError.
  ///
  /// In en, this message translates to:
  /// **'Location is unavailable. Check location access and try again.'**
  String get locationError;

  /// No description provided for @nfcError.
  ///
  /// In en, this message translates to:
  /// **'NFC is unavailable. Check NFC settings and try again.'**
  String get nfcError;

  /// No description provided for @notificationError.
  ///
  /// In en, this message translates to:
  /// **'Notifications are unavailable. Check notification settings.'**
  String get notificationError;

  /// No description provided for @conflictError.
  ///
  /// In en, this message translates to:
  /// **'The information changed elsewhere. Refresh and try again.'**
  String get conflictError;

  /// No description provided for @notFoundError.
  ///
  /// In en, this message translates to:
  /// **'The requested information could not be found.'**
  String get notFoundError;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. Please try again.'**
  String get unknownError;

  /// No description provided for @arrivedAtStop.
  ///
  /// In en, this message translates to:
  /// **'Arrived — {stop}'**
  String arrivedAtStop(String stop);

  /// No description provided for @studentsExpected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 student expected} other{{count} students expected}}'**
  String studentsExpected(int count);

  /// No description provided for @onBoard.
  ///
  /// In en, this message translates to:
  /// **'On board'**
  String get onBoard;

  /// No description provided for @waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get waiting;

  /// No description provided for @assignedStudentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 student} other{{count} students}}'**
  String assignedStudentsCount(int count);

  /// No description provided for @studentRoster.
  ///
  /// In en, this message translates to:
  /// **'Student roster'**
  String get studentRoster;

  /// No description provided for @studentsAssignedToCurrentTrip.
  ///
  /// In en, this message translates to:
  /// **'Students assigned to the current trip'**
  String get studentsAssignedToCurrentTrip;

  /// No description provided for @correctAttendance.
  ///
  /// In en, this message translates to:
  /// **'Correct attendance'**
  String get correctAttendance;

  /// No description provided for @allStudents.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allStudents;

  /// No description provided for @notBoarded.
  ///
  /// In en, this message translates to:
  /// **'Not boarded'**
  String get notBoarded;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @pendingSync.
  ///
  /// In en, this message translates to:
  /// **'Pending sync'**
  String get pendingSync;

  /// No description provided for @noAttendanceEventYet.
  ///
  /// In en, this message translates to:
  /// **'No attendance event yet'**
  String get noAttendanceEventYet;

  /// No description provided for @manualAttendanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Manual attendance: {studentName}'**
  String manualAttendanceTitle(String studentName);

  /// No description provided for @nextActionCheckOut.
  ///
  /// In en, this message translates to:
  /// **'Next action: Check out'**
  String get nextActionCheckOut;

  /// No description provided for @nextActionCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Next action: Check in'**
  String get nextActionCheckIn;

  /// No description provided for @selectReason.
  ///
  /// In en, this message translates to:
  /// **'Select a reason.'**
  String get selectReason;

  /// No description provided for @attendanceSaved.
  ///
  /// In en, this message translates to:
  /// **'Attendance saved for {studentName}.'**
  String attendanceSaved(String studentName);

  /// No description provided for @attendanceQueued.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device for {studentName} — waiting to sync.'**
  String attendanceQueued(String studentName);

  /// No description provided for @attendanceStopSummary.
  ///
  /// In en, this message translates to:
  /// **'{total} total · {waitingCount} waiting · {onboardCount} onboard · {completedCount} completed'**
  String attendanceStopSummary(
    int total,
    int waitingCount,
    int onboardCount,
    int completedCount,
  );

  /// No description provided for @cardForgotten.
  ///
  /// In en, this message translates to:
  /// **'Card forgotten'**
  String get cardForgotten;

  /// No description provided for @cardUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Card unreadable'**
  String get cardUnreadable;

  /// No description provided for @nfcUnavailable.
  ///
  /// In en, this message translates to:
  /// **'NFC unavailable'**
  String get nfcUnavailable;

  /// No description provided for @adminInstruction.
  ///
  /// In en, this message translates to:
  /// **'Admin instruction'**
  String get adminInstruction;

  /// No description provided for @pickupStops.
  ///
  /// In en, this message translates to:
  /// **'Pickup stops'**
  String get pickupStops;

  /// No description provided for @dropoffStops.
  ///
  /// In en, this message translates to:
  /// **'Drop-off stops'**
  String get dropoffStops;

  /// No description provided for @noStudentsInCategory.
  ///
  /// In en, this message translates to:
  /// **'No students in this category'**
  String get noStudentsInCategory;

  /// No description provided for @unknownUnassignedStop.
  ///
  /// In en, this message translates to:
  /// **'Unknown or unassigned stop'**
  String get unknownUnassignedStop;

  /// No description provided for @boardedAt.
  ///
  /// In en, this message translates to:
  /// **'Boarded at {time}'**
  String boardedAt(String time);

  /// No description provided for @droppedOffAt.
  ///
  /// In en, this message translates to:
  /// **'Dropped off at {time}'**
  String droppedOffAt(String time);

  /// No description provided for @attendanceSavedForStudent.
  ///
  /// In en, this message translates to:
  /// **'Saved: {studentName}'**
  String attendanceSavedForStudent(String studentName);

  /// No description provided for @routePointWithCoordinates.
  ///
  /// In en, this message translates to:
  /// **'Route point {number} ({latitude}, {longitude})'**
  String routePointWithCoordinates(
    int number,
    String latitude,
    String longitude,
  );

  /// No description provided for @backTooltip.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backTooltip;

  /// No description provided for @plannedRoutesLabel.
  ///
  /// In en, this message translates to:
  /// **'Planned routes'**
  String get plannedRoutesLabel;

  /// No description provided for @newRouteTitle.
  ///
  /// In en, this message translates to:
  /// **'New route'**
  String get newRouteTitle;

  /// No description provided for @editRouteTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit route'**
  String get editRouteTitle;

  /// No description provided for @routePlannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Route planner'**
  String get routePlannerTitle;

  /// No description provided for @routeCreated.
  ///
  /// In en, this message translates to:
  /// **'Route created'**
  String get routeCreated;

  /// No description provided for @routeSaved.
  ///
  /// In en, this message translates to:
  /// **'Route saved'**
  String get routeSaved;

  /// No description provided for @saveFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailedWithError(String error);

  /// No description provided for @deleteFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailedWithError(String error);

  /// No description provided for @moreOptionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptionsTooltip;

  /// No description provided for @routeMaxStopsReached.
  ///
  /// In en, this message translates to:
  /// **'Google routes support at most {max} stops per route.'**
  String routeMaxStopsReached(int max);

  /// No description provided for @routeStopsPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Stops'**
  String get routeStopsPanelTitle;

  /// No description provided for @routeStopCounter.
  ///
  /// In en, this message translates to:
  /// **'{count} / {max} stops'**
  String routeStopCounter(int count, int max);

  /// No description provided for @routeTooManyStopsForGoogle.
  ///
  /// In en, this message translates to:
  /// **'This route has {count} stops. Google supports at most {max}. Remove stops or split the route.'**
  String routeTooManyStopsForGoogle(int count, int max);

  /// No description provided for @removeStopTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove stop'**
  String get removeStopTooltip;

  /// No description provided for @routeStopNumber.
  ///
  /// In en, this message translates to:
  /// **'Stop {number}'**
  String routeStopNumber(int number);

  /// No description provided for @routeSplitMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Split into two routes'**
  String get routeSplitMenuTitle;

  /// No description provided for @routeSplitDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Split route'**
  String get routeSplitDialogTitle;

  /// No description provided for @routeSplitAfterLabel.
  ///
  /// In en, this message translates to:
  /// **'Split after stop {stop}'**
  String routeSplitAfterLabel(int stop);

  /// No description provided for @routeShareJunctionLabel.
  ///
  /// In en, this message translates to:
  /// **'Start part 2 from stop {stop} (connected parts)'**
  String routeShareJunctionLabel(int stop);

  /// No description provided for @routeSplitPreview.
  ///
  /// In en, this message translates to:
  /// **'Part 1: {first} stops • Part 2: {second} stops'**
  String routeSplitPreview(int first, int second);

  /// No description provided for @routeSplitOptionsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Both parts need 2–{max} stops.'**
  String routeSplitOptionsInvalid(int max);

  /// No description provided for @routeSplitConfirm.
  ///
  /// In en, this message translates to:
  /// **'Split & save'**
  String get routeSplitConfirm;

  /// No description provided for @routeSplitting.
  ///
  /// In en, this message translates to:
  /// **'Computing Google geometry and saving both routes…'**
  String get routeSplitting;

  /// No description provided for @routePartName.
  ///
  /// In en, this message translates to:
  /// **'Part {number}'**
  String routePartName(int number);

  /// No description provided for @routeSplitDone.
  ///
  /// In en, this message translates to:
  /// **'Created \"{first}\" and \"{second}\".'**
  String routeSplitDone(String first, String second);

  /// No description provided for @routeSplitFailed.
  ///
  /// In en, this message translates to:
  /// **'Split failed: {error}'**
  String routeSplitFailed(String error);

  /// No description provided for @routeGeometryUnavailableBanner.
  ///
  /// In en, this message translates to:
  /// **'Route geometry unavailable — run Rebuild Route Geometry.'**
  String get routeGeometryUnavailableBanner;

  /// No description provided for @routeSplitBlockedActiveTrip.
  ///
  /// In en, this message translates to:
  /// **'A trip is active on this route. Wait until it completes before splitting.'**
  String get routeSplitBlockedActiveTrip;

  /// No description provided for @routeSplitDependentsInfo.
  ///
  /// In en, this message translates to:
  /// **'{students} student(s) and {buses} bus(es) are assigned to this route and will be updated automatically.'**
  String routeSplitDependentsInfo(int students, int buses);

  /// No description provided for @routeSplitBusTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Reassign assigned buses to'**
  String get routeSplitBusTargetLabel;

  /// No description provided for @routeSplitKeepUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Leave unassigned'**
  String get routeSplitKeepUnassigned;

  /// No description provided for @routeSaveShiftWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop order will change'**
  String get routeSaveShiftWarningTitle;

  /// No description provided for @routeSaveShiftWarningBody.
  ///
  /// In en, this message translates to:
  /// **'{count} student assignment(s) point at stops of this route by position. Changing stop order moves them to different physical stops.'**
  String routeSaveShiftWarningBody(int count);

  /// No description provided for @saveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get saveAnyway;

  /// No description provided for @routeGeometryFailedKeepOriginal.
  ///
  /// In en, this message translates to:
  /// **'Google could not compute road geometry for the new parts. The original route was kept.'**
  String get routeGeometryFailedKeepOriginal;

  /// No description provided for @routeSplitMigratedSummary.
  ///
  /// In en, this message translates to:
  /// **'{students} student(s) • {buses} bus(es) reassigned.'**
  String routeSplitMigratedSummary(int students, int buses);

  /// No description provided for @routeSplitCrossPartWarning.
  ///
  /// In en, this message translates to:
  /// **'{count} student(s) have pickup and dropoff on different parts — please review them.'**
  String routeSplitCrossPartWarning(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
