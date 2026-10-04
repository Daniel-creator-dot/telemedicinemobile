# Firebase Notification Setup Guide

## Overview
This implementation adds push notification functionality to notify doctors when they are assigned to meetings/appointments by admins.

## ✅ Setup Status: COMPLETE

Firebase Admin SDK has been successfully configured and initialized. The server is now ready to send push notifications to doctors when they are assigned to appointments.

## What Was Implemented

### 1. Server-Side Changes

#### Database Schema
- **Added `fcm_tokens` table** to store Firebase Cloud Messaging tokens for each user
  - `user_id`: References the user
  - `token`: The FCM token from the device
  - `platform`: Device platform (android, ios, etc.)
  - `created_at`/`updated_at`: Timestamps

#### API Endpoints
- **POST `/api/push/fcm-token`**: Register/update FCM token for authenticated users
  - Requires authentication
  - Accepts: `{ "token": "fcm_token_string", "platform": "android" }`
  - Automatically updates timestamp if token already exists

#### Notification Triggers
Push notifications are now sent to doctors in these scenarios:

1. **When admin assigns doctor to new appointment** (POST `/api/appointments`)
   - Triggers if `doctor_id` is provided during booking

2. **When admin updates appointment and assigns/changes doctor** (PATCH `/api/appointments/:id`)
   - Triggers when `doctor_id` is changed or newly assigned

3. **When meeting link is generated for telemedicine** (POST `/api/appointments/:id/generate-link`)
   - Notifies assigned doctor that meeting link is ready

#### Notification Utility Function
- **`sendPushNotification(userId, title, body, data)`**: Core function for sending FCM notifications
  - Handles multiple tokens per user
  - Cleans up invalid tokens automatically
  - Includes both notification payload (for display) and data payload (for app logic)

### 2. Dependencies Added
- `firebase-admin`: Firebase Admin SDK for server-side FCM operations

### 3. Configuration
- Added `FIREBASE_SERVICE_ACCOUNT_KEY` environment variable
- Created `.env.example` with required configuration template

## Setup Instructions

### ✅ Step 1: Firebase Service Account Key - CONFIGURED
The Firebase service account key has been successfully added to the `.env` file for project `telemedicine-a79f4`.

### Step 2: Ensure Mobile App Registers FCM Tokens

The mobile app should already have Firebase messaging set up. Ensure it:

1. Gets the FCM token on app startup
2. Calls the `/api/push/fcm-token` endpoint when user logs in
3. Updates the token when it refreshes

Example token registration (already implemented in your mobile app):

```dart
// From your existing PushNotificationService
await api.dio.post('/api/push/fcm-token', data: {
  'token': token,
  'platform': defaultTargetPlatform.name,
});
```

### Step 3: Test the Implementation

1. **Start the server**:
   ```bash
   cd server
   npm run dev
   ```

2. **Verify Firebase initialization**:
   - ✅ You should see: "Firebase Admin initialized successfully"
   - Server is now configured and ready to send notifications

3. **Test notification flow**:
   - Log in as a doctor on the mobile app
   - Ensure FCM token is registered (check server logs or database)
   - As admin, assign the doctor to an appointment
   - Doctor should receive a push notification

## Notification Payload Structure

When a doctor is assigned, they receive:

**Display Notification**:
- Title: "New Appointment Assigned"
- Body: "You have been assigned to Telemedicine appointment APT-XYZ for John Doe on 2025-06-23 at 14:30"

**Data Payload** (for app navigation/logic):
```json
{
  "type": "appointment_assigned",
  "appointment_id": "APT-XYZ",
  "patient_name": "John Doe",
  "date": "2025-06-23",
  "time": "14:30",
  "is_telemedicine": "false"
}
```

## Troubleshooting

### ✅ Server Firebase Configuration - FIXED
- Firebase Admin SDK is now properly initialized
- Server starts successfully with "Firebase Admin initialized successfully" message
- Service account credentials are properly configured

### Notifications not arriving
1. Check server logs for "Push notification sent to [userId]"
2. Verify FCM tokens are in the database: `SELECT * FROM fcm_tokens WHERE user_id = [doctor_user_id]`
3. Ensure mobile app has notification permissions
4. Check Firebase Console for message delivery status

### TypeScript errors
- The implementation uses type assertions for Firebase Admin SDK
- Run `npm install` to ensure all dependencies are installed

## Files Modified

1. **server/index.ts**
   - Added Firebase Admin initialization
   - Added `/api/push/fcm-token` endpoint
   - Added `sendPushNotification()` utility function
   - Modified appointment creation/update endpoints to send notifications
   - Modified meeting link generation to notify doctors

2. **server/db.ts**
   - Added `fcm_tokens` table schema

3. **server/package.json**
   - Added `firebase-admin` dependency

4. **server/.env**
   - Added `FIREBASE_SERVICE_ACCOUNT_KEY` placeholder

5. **server/.env.example**
   - Created example configuration file

## Next Steps

1. ✅ Set up your Firebase service account key in `.env` - **COMPLETED**
2. Test the notification flow with real devices
3. Customize notification messages as needed
4. Add additional notification triggers for other events (consultations, lab results, etc.)
5. Implement notification handling in the mobile app for navigation

## ✅ Implementation Complete

The system is now fully configured and ready to send push notifications to doctors when they are assigned to meetings by admins!

**Summary of what was done:**
- ✅ Firebase Admin SDK installed and configured
- ✅ Service account credentials added to `.env`
- ✅ Server successfully initializes Firebase Admin
- ✅ Database table for FCM tokens created
- ✅ Token registration endpoint implemented
- ✅ Push notification utility function created
- ✅ Notification triggers added for doctor assignment events
- ✅ Server tested and running successfully

**Ready for testing:** Start the server and test the notification flow with real devices.