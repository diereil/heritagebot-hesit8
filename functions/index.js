const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

admin.initializeApp();

const db = admin.firestore();

const OTP_EXPIRY_MINUTES = 10;
const MAX_ATTEMPTS = 5;

function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function createOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function hashValue(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function otpDocumentId(email) {
  return hashValue(email);
}

function hashOtp(otp, salt) {
  return hashValue(`${otp}:${salt}`);
}

function requireEmailConfig() {
  if (!process.env.GMAIL_EMAIL || !process.env.GMAIL_APP_PASSWORD) {
    throw new HttpsError(
      "failed-precondition",
      "Email sender is not configured. Please set GMAIL_EMAIL and GMAIL_APP_PASSWORD in functions/.env."
    );
  }
}

function createTransporter() {
  requireEmailConfig();

  return nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: process.env.GMAIL_EMAIL,
      pass: process.env.GMAIL_APP_PASSWORD,
    },
  });
}

exports.sendSignupOtp = onCall(async (request) => {
  const email = normalizeEmail(request.data.email);

  if (!isValidEmail(email)) {
    throw new HttpsError("invalid-argument", "Please enter a valid email address.");
  }

  const otp = createOtp();
  const salt = crypto.randomBytes(16).toString("hex");
  const otpHash = hashOtp(otp, salt);
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000
  );

  const docId = otpDocumentId(email);

  await db.collection("signupOtps").doc(docId).set({
    email,
    otpHash,
    salt,
    attempts: 0,
    expiresAt,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const transporter = createTransporter();

  await transporter.sendMail({
    from: `"HeritageBot" <${process.env.GMAIL_EMAIL}>`,
    to: email,
    subject: "Your HeritageBot OTP Verification Code",
    text: `Your HeritageBot OTP code is ${otp}. This code will expire in ${OTP_EXPIRY_MINUTES} minutes.`,
    html: `
      <div style="font-family: Arial, sans-serif; padding: 20px;">
        <h2>HeritageBot Email Verification</h2>
        <p>Your OTP code is:</p>
        <h1 style="letter-spacing: 6px;">${otp}</h1>
        <p>This code will expire in ${OTP_EXPIRY_MINUTES} minutes.</p>
        <p>If you did not request this, you can ignore this email.</p>
      </div>
    `,
  });

  return {
    ok: true,
    message: "OTP sent successfully.",
  };
});

exports.verifySignupOtp = onCall(async (request) => {
  const email = normalizeEmail(request.data.email);
  const otp = String(request.data.otp || "").trim();

  if (!isValidEmail(email)) {
    throw new HttpsError("invalid-argument", "Invalid email address.");
  }

  if (!/^\d{6}$/.test(otp)) {
    throw new HttpsError("invalid-argument", "OTP must be 6 digits.");
  }

  const docId = otpDocumentId(email);
  const ref = db.collection("signupOtps").doc(docId);
  const snap = await ref.get();

  if (!snap.exists) {
    throw new HttpsError("not-found", "OTP not found. Please request a new code.");
  }

  const data = snap.data();

  if (!data.expiresAt || data.expiresAt.toMillis() < Date.now()) {
    await ref.delete();
    throw new HttpsError("deadline-exceeded", "OTP expired. Please request a new code.");
  }

  if ((data.attempts || 0) >= MAX_ATTEMPTS) {
    await ref.delete();
    throw new HttpsError(
      "resource-exhausted",
      "Too many incorrect attempts. Please request a new OTP."
    );
  }

  const submittedHash = hashOtp(otp, data.salt);

  if (submittedHash !== data.otpHash) {
    await ref.update({
      attempts: admin.firestore.FieldValue.increment(1),
      lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    throw new HttpsError("permission-denied", "Incorrect OTP code.");
  }

  await ref.delete();

  return {
    ok: true,
    message: "OTP verified successfully.",
  };
});