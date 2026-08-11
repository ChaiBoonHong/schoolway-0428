# SchoolWay FYP2 Report Comparison

## 1. Project Change Report

Repository: [schoolway-0428](https://github.com/ChaiBoonHong/schoolway-0428)

Local current commit: `2376616` — 25 July 2026.

### May 5, 2026 commits

The May 5 commits mainly prepared the initial project for deployment:

- Improved CSV import validation and added driver seed data.
- Added trip direction and richer trip history.
- Added boarding alerts to push notifications.
- Added GitHub Pages deployment.
- Fixed Flutter Web `base href` configuration.
- Updated the project README with logo and badges.
- Removed old hosting files and legacy dependencies.

Several commits appear duplicated in the local history.

### Current system compared with May 5

| Area | May 5 version | Current version |
|---|---|---|
| Authentication | Basic project setup | Email/Google login, profile completion and role-based routing |
| Admin | Limited management | Users, students, buses, routes, CSV import, emergency alerts, reports and attendance correction |
| Driver | Basic trip functions | Trip start/end, trip direction, student roster, NFC/manual boarding, GPS tracking and incident reporting |
| Parent | Basic monitoring concept | Children dashboard, live map, trip history, notification inbox and preferences |
| Attendance | Initial NFC/import support | NFC boarding and alighting, manual fallback and event history |
| Notifications | Boarding alerts | Firebase Cloud Messaging, notification preferences and quiet hours |
| Tracking | Basic GPS concept | Live maps, route history, ETA/geofence-related services and stationary-bus detection |
| Reliability | Basic imports | Offline queue, retry handling, latency tracking and stress-test tools |
| Deployment | GitHub Pages setup | Firebase Functions, Flutter Web configuration and expanded deployment support |

After the May 5 baseline, the local checkout contains approximately 67 relevant source/configuration files changed, with about 10,382 additions and 1,227 deletions, excluding generated `functions/node_modules` files.

### Verification required before submission

- Test all functions on real devices.
- Confirm NFC works on supported Android devices.
- Measure real notification and GPS latency.
- Strengthen Firestore role-based security rules.
- Confirm `serviceAccountKey.json` and generated dependencies do not expose sensitive data.

## 2. Main Current Functions

1. Role-based authentication for administrators, drivers and parents.
2. Student, bus, driver and route management.
3. CSV bulk import and validation.
4. NFC boarding and alighting recording.
5. Manual attendance fallback.
6. Driver trip management and trip direction.
7. GPS location uploading and live map display.
8. Parent child monitoring and trip history.
9. Push notifications and notification preferences.
10. Emergency alert management.
11. Attendance correction and incident reporting.
12. Offline queue and retry support.
13. Route history and operational reports.
14. ETA/geofence-related services.
15. Flutter Web and Firebase deployment configuration.

These functions provide the main evidence for FYP2 Chapters 4, 5 and 6.

## 3. FYP1 and FYP2 Structure Differences

### FYP1 submitted structure

The submitted FYP1 report contains preliminary pages, Chapters 1–5, references and an appendix. It covers the literature review, development methodology, requirements, preliminary design, software setup, initial implementation, system operation, implementation challenges, conclusion, limitations and future work.

FYP1 focuses on proposal, feasibility, prototype development and planned Project II work.

### FYP2 required structure

FYP2 expands the report to Chapters 1–7 and requires completed system design, detailed implementation, system evaluation, testing results, optional questionnaire results, objective achievement evidence, conclusion and recommendations.

| FYP1 section | FYP2 change |
|---|---|
| Chapter 1: Introduction | Retain, but change proposed-system wording to completed-system wording |
| Chapter 2: Literature Review | Retain and update with final technologies and stronger comparison |
| Chapter 3: Methodology | Add non-functional requirements, estimated cost and explained Project I/II milestones |
| FYP1 Chapter 3.3: System Design | Move to FYP2 Chapter 4 |
| FYP1 Chapter 4: Setup and Implementation | Separate into FYP2 Chapters 4 and 5 |
| FYP1 Chapter 4.4: Challenges | Move mainly to FYP2 Chapter 6.3 |
| FYP1 Chapter 5: Conclusion | Replace with final evaluation in Chapter 6 and final conclusion in Chapter 7 |
| Limitations and future work | Expand into FYP2 Chapter 7.2 |
| Testing | Add dedicated setup, test cases and results |
| Objectives | Add evidence showing how each objective was achieved |

## 4. Recommended FYP2 Structure

### Preliminary pages

- Title page
- Acknowledgements
- Copyright statement
- Abstract
- Table of contents
- List of figures
- List of tables
- List of abbreviations

### Chapter 1 - Introduction

1.1 Project Background  
1.2 Problem Statement and Motivation  
1.3 Project Objectives  
1.4 Project Contribution  
1.5 Project Scope  
1.6 Report Organization

Update this chapter to describe SchoolWay as an implemented system.

### Chapter 2 - Literature Review

Discuss school transportation monitoring, Flutter, NFC attendance, GPS tracking, Firebase, push notifications, existing school bus systems and the research gap addressed by SchoolWay.

### Chapter 3 - System Methodology

3.1 System Development Models  
3.2 System Requirements  
3.3 Functional and Non-Functional Requirements  
3.4 Project Milestone  
3.4.1 Project I Timeline with explanation  
3.4.2 Project II Timeline with explanation  
3.5 Estimated Cost  
3.6 Concluding Remark

### Chapter 4 - System Design

4.1 System Architecture  
4.2 Use Case Diagram  
4.3 Activity Diagram  
4.4 Database Design  
4.5 Concluding Remark

Include administrator, driver and parent workflow diagrams.

### Chapter 5 - System Implementation

5.1 Software/Hardware Setup and Configuration  
5.2 Implementation Details  
5.3 System Operation  
5.4 Concluding Remark

Include evidence for authentication, admin management, driver trips, NFC attendance, GPS maps, parent monitoring, notifications, CSV import, reports and alerts.

### Chapter 6 - System Evaluation and Discussion

6.1 System Performance Evaluation  
6.2 System Testing Setup and Result  
6.2 Questionnaire, if applicable  
6.3 Project Challenges  
6.4 Objectives Evaluation  
6.5 Concluding Remark

Recommended evidence includes functional test cases, NFC accuracy, notification delay, GPS latency, CSV validation, cross-role access tests, questionnaire results and an objective-to-feature mapping.

### Chapter 7 - Conclusion and Recommendation

7.1 Conclusion  
7.2 Recommendation/Future Work

Discuss stronger security rules, offline synchronization, ETA prediction, geo-fencing, larger-scale testing, analytics and production hardening.

## 5. Chapter Reorganization

| FYP1 | FYP2 |
|---|---|
| Chapter 3.3 System Design | Chapter 4 System Design |
| Chapter 4.1–4.3 Setup, implementation and operation | Chapter 5 System Implementation |
| Chapter 4.4 Challenges | Chapter 6.3 Project Challenges |
| Chapter 5 Conclusion, limitations and future work | Chapters 6 and 7 |

The main FYP2 requirement is measurable evaluation. Screenshots should be supported by test cases, performance results and evidence that each objective was achieved.

## Source

Submitted FYP1 report: `docs/Chai Boon Hong Report.pdf`

## 6. Tutor Guideline Requirements

### Abstract

- Length: 150–300 words.
- No citations.
- Write it after completing the report.
- Cover introduction/background, problem statement, unique selling point, research gap, aim/objective, method, significance/results/contribution.
- Answer what problem is solved, why it matters, what solution is proposed, how it was developed, what results were obtained and why the project matters.
- Keep the writing concise and avoid unnecessary technical details.

### Chapter 2 - Literature Review

For each technology or existing system:

1. Introduce the topic.
2. Describe its technical characteristics.
3. Explain strengths and weaknesses.
4. Compare alternatives in a table.
5. Explain which option SchoolWay uses and why.

Recommended SchoolWay subsections:

- 2.1.1 Field of Study: school transportation management.
- 2.1.2 Operating System/Framework.
  - Android
  - iOS
  - Flutter
  - Summary and selection justification
- 2.1.3 Algorithms/Methods, where applicable.
- 2.1.4 Database.
  - Candidate database technologies
  - Summary and Firebase selection justification
- 2.2 Existing Systems/Applications.
  - Each system: introduction, strengths, weaknesses and unresolved gap
  - Proposed SchoolWay system and comparison table

Use credible references and apply the required UTAR citation style consistently.

### Chapter 3.3 - Functional and Non-Functional Requirements

Functional requirements must:

- Identify core system functions.
- Describe system behaviour from the user’s perspective.
- Link directly to project objectives and scope.
- Use a table or diagram plus written explanations.

Non-functional requirements must define measurable quality expectations, such as:

- NFR001 Performance
- NFR002 Security
- NFR003 Reliability
- NFR004 Usability
- NFR005 Compatibility
- NFR006 Availability
- NFR007 Scalability

Each requirement should state a realistic expected standard.

### Chapter 3.4 - Project Milestone

- Divide the work into major development phases and deliverables.
- Include a realistic Gantt chart.
- Provide separate Project I and Project II timelines.
- Explain the purpose and outcome of each major phase.
- Align the schedule with the selected development model and university deadlines.
- Avoid daily-level detail and unrealistic timelines.

### Chapter 3.5 - Estimated Cost

The tutor guideline marks this as not applicable. State that the project has no estimated development cost because the software tools and libraries are downloadable and used without charge. Mention any optional hardware or service cost only if it was actually incurred.

### Chapter 4 - System Design

#### 4.1 System Architecture

Explain the major components, relationships and data flows. For SchoolWay, cover Flutter, Firebase Authentication, Firestore/Realtime Database, Firebase Cloud Messaging, GPS, NFC, maps and the role-based modules.

#### 4.2 Use Case Diagram

Show the actors and their interactions with the system. The main actors are Administrator, Driver and Parent. Explain every major use case after the diagram.

#### 4.3 Activity Diagram

Provide activity diagrams for important workflows. Each diagram needs an introduction and explanation. The diagrams must match the functional and non-functional requirements.

#### 4.4 Database Design

Describe the database structure using tables containing field name, data type, field size where applicable and field description. Cover the main SchoolWay collections, relationships and security-relevant data.

### Chapter 5 - System Implementation

#### 5.1 Setup and Configuration

Focus on installation and configuration rather than feature code. Possible subsections are:

- Environment preparation
- External service integration
- Database configuration
- Cloud services
- Deployment and hosting
- Monitoring and analytics

#### 5.2 Implementation Details

Explain how each feature was coded and integrated. Include relevant algorithms, data structures, permissions, configuration and short code extracts where useful. GPS, NFC and permission implementation details belong here rather than in 5.1.

#### 5.3 System Operation

For FYP2, provide screenshots and explanations for every developed module. Planned-but-unimplemented layouts should not replace completed-system evidence. Cover authentication, admin, driver, parent, NFC, GPS, notifications, CSV import, reports and alerts.

### Chapter 6 - System Evaluation and Discussion

#### 6.1 Performance Evaluation

Possible subsections include:

- Load testing
- Response-time analysis
- Network performance
- Database performance

Record repeated measurements, present graphs or tables, compare results with the requirements and state whether the expected performance was achieved.

#### 6.2 Testing Setup and Results

Describe the test cases for the functional requirements. State how many times each test was performed and whether it passed or failed.

#### Questionnaire

The questionnaire is optional. If used, include respondent information, design feedback, application evaluation, security concerns, encountered errors and non-functional performance feedback.

#### 6.3 Project Challenges and 6.4 Objectives Evaluation

The tutor guideline marks both sections as not applicable in the supplied text. The report should still include concise project-specific content if the FYP2 template requires these headings: list actual challenges and map every objective to implemented features and evidence.
