// Copyright 2022-2025 Ilya Zverev
// This file is a part of Every Door, distributed under GPL v3 or later version.
// Refer to LICENSE file and https://www.gnu.org/licenses/gpl-3.0.html for details.
import 'dart:convert' show json;

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:every_door/fields/text.dart';
import 'package:every_door/helpers/auth/provider.dart';
import 'package:every_door/helpers/editor_fields.dart';
import 'package:every_door/helpers/multi_icon.dart';
import 'package:every_door/models/field.dart';
import 'package:every_door/plugins/every_door_plugin.dart';
import 'package:every_door/plugins/interface.dart';
import 'package:every_door/screens/modes/definitions/amenity.dart';
import 'package:every_door/screens/modes/definitions/classic.dart';
import 'package:every_door/models/amenity.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class PluginUnderConstruction extends EveryDoorPlugin {
  static const kEnabled = true;

  static Map<String, dynamic> getMetadata() => {
        'id': 'pluginUnderConstruction',
        'name': 'Plugin Under Construction',
      };

  @override
  Future<void> install(EveryDoorApp app) async {
    app.removeMode('micro');
    app.addMode(MicroAsPoi.fromPlugin(app));
  }
}

class MicroAsPoi extends AmenityModeDefinition {
  MicroAsPoi.fromPlugin(super.app) : super.fromPlugin();

  @override
  String get name => 'micro_poi';
}


class PanoramaxToken extends AuthToken {
  final String jwt;
  final String id;

  const PanoramaxToken(this.id, this.jwt);

  factory PanoramaxToken.fromJson(Map<String, dynamic> data) =>
      PanoramaxToken(data['id'], data['jwt_token']);

  @override
  Map<String, dynamic> toJson() => {'id': id, 'jwt_token': jwt};
}

class PanoramaxAuth extends AuthProvider {
  @override
  String get endpoint => 'panoramax.openstreetmap.fr';

  @override
  String? get title => 'Panoramax';

  @override
  MultiIcon? get icon => MultiIcon(
      imageUrl: 'https://docs.panoramax.fr/images/panoramax_favicon.svg');

  @override
  Future<UserDetails> loadUserDetails(AuthToken token) async {
    final response = await http.get(Uri.https(endpoint, '/api/users/me'),
        headers: getHeaders(token));
    if (response.statusCode != 200) {
      throw AuthException("Failed to get user data");
    }
    final data = json.decode(response.body);
    return UserDetails(displayName: data['name']);
  }

  @override
  Future<void> logout(AuthToken token) async {
    await http.get(Uri.https(endpoint, '/api/auth/logout'),
        headers: getHeaders(token));
    await super.logout(token);
  }

  @override
  Future<bool> testHeaders(Map<String, String>? headers, String? apiKey) async {
    final response =
        await http.get(Uri.https(endpoint, '/api/users/me'), headers: headers);
    return response.statusCode == 200;
  }

  @override
  Future<AuthToken?> login(BuildContext context) async {
    final tokenRequest =
        await http.post(Uri.https(endpoint, '/api/auth/tokens/generate'));
    if (tokenRequest.statusCode != 200) {
      throw AuthException('Failed to generate a blank token.');
    }
    final token = PanoramaxToken.fromJson(json.decode(tokenRequest.body));

    final claimUrl = Uri.https(endpoint, 'api/auth/tokens/${token.id}/claim');
    if (!context.mounted) return null;
    await showOkAlertDialog(
        context: context,
        message:
            'You will be shown the Panoramax website. Please login through to the confirmation message, and then close it and return to the app.');
    await launchUrl(claimUrl, mode: LaunchMode.inAppBrowserView);
    if (context.mounted) {
      await showOkAlertDialog(
          context: context, message: 'Please tap "OK" when done.');
    }
    return token;
  }

  @override
  AuthToken tokenFromJson(Map<String, dynamic> data) =>
      PanoramaxToken.fromJson(data);

  @override
  Map<String, String> getHeaders(AuthToken token) => {
        'Authorization': 'Bearer ${(token as PanoramaxToken).jwt}',
      };
}
