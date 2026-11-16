'use strict';
// Cross-language test vector. The SAME constants are checked by the Unreal
// automation test "PUBG.RoomService.TicketVector" (PUBGAutomationTests.cpp),
// which runs the C++ verifier (FSHA1::HMACBuffer). If both pass, the service and
// the dedicated server agree on the ticket format.
const test = require('node:test');
const assert = require('node:assert/strict');
const { makeTicket, verifyTicket } = require('../src/rooms');

const SECRET = 'unit-test-secret';
const ROOM = 'room42';
const PLAYER = 'Alice';
const EXPIRES = 1999999999;
const EXPECTED = 'cm9vbTQyfEFsaWNlfDE5OTk5OTk5OTk.855bb9674961ccfcdd6d9d54781ef24c4dc9250b';

test('ticket vector matches the constant shared with the C++ test', () => {
  assert.equal(makeTicket(SECRET, ROOM, PLAYER, EXPIRES), EXPECTED);
  assert.deepEqual(verifyTicket(EXPECTED, SECRET, ROOM, EXPIRES), { ok: true, playerName: PLAYER });
  assert.equal(verifyTicket(EXPECTED, SECRET, ROOM, EXPIRES + 1).ok, false);
});
