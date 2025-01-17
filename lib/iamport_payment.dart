import 'dart:io';
import 'package:dart_json_mapper/dart_json_mapper.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:iamport_webview_flutter/iamport_webview_flutter.dart';
import './widget/iamport_error.dart';
import './widget/iamport_webview.dart';
import './model/iamport_validation.dart';
import './model/payment_data.dart';
import './model/url_data.dart';

class IamportPayment extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Container? initialChild;
  final String userCode;
  final PaymentData data;
  final callback;

  IamportPayment({
    Key? key,
    this.appBar,
    this.initialChild,
    required this.userCode,
    required this.data,
    required this.callback,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    IamportValidation validation =
        IamportValidation(this.userCode, this.data, this.callback);

    if (validation.getIsValid()) {
      return IamportWebView(
        type: ActionType.payment,
        appBar: this.appBar,
        initialChild: this.initialChild,
        executeJS: (WebViewController? controller) {
          controller?.evaluateJavascript('''
            IMP.init("${this.userCode}");
            IMP.request_pay(${JsonMapper.serialize(this.data)}, function(response) {
              const query = [];
              Object.keys(response).forEach(function(key) {
                query.push(key + "=" + response[key]);
              });
              location.href = "${UrlData.redirectUrl}" + "?" + query.join("&");
            });
          ''');

          try {
            String url = controller?.currentUrl() as String;
            String decodedUrl = Uri.decodeComponent(url);
            Uri parsedUrl = Uri.parse(decodedUrl);
            String scheme = parsedUrl.scheme;
            if (scheme == this.data.appScheme.toLowerCase() &&
                this.data.pg == 'nice' &&
                this.data.payMethod == 'trans') {
              String queryToString = parsedUrl.query;

              /* [v0.9.6] niceMobileV2: true 대비 코드 작성 */
              String? niceTransRedirectionUrl;
              parsedUrl.queryParameters.forEach((key, value) {
                if (key == 'callbackparam1') {
                  niceTransRedirectionUrl = value;
                }
              });
              controller?.evaluateJavascript('''
                location.href = "$niceTransRedirectionUrl?$queryToString";
              ''');
            }
          } on FormatException {}
        },
        customPGAction: (WebViewController? controller, String? data) {
          if (this.data.pg == 'smilepay') {
            // webview_flutter에서 iOS는 쿠키가 기본적으로 허용되어있는 것으로 추정
            if (Platform.isAndroid) {
              controller?.setAcceptThirdPartyCookies(true);
            }
            // controller?.loadDataWithBaseURL(
            //     IamportUrl.SMILE_PAY_BASE_URL, data!, 'text/html', null, null);
          }
        },
        useQueryData: (Map<String, String> data) {
          this.callback(data);
        },
        isPaymentOver: (String url) {
          if (url.startsWith(UrlData.redirectUrl)) {
            return true;
          }

          if (this.data.payMethod == 'trans') {
            /* [IOS] imp_uid와 merchant_uid값만 전달되기 때문에 결제 성공 또는 실패 구분할 수 없음 */
            String decodedUrl = Uri.decodeComponent(url);
            Uri parsedUrl = Uri.parse(decodedUrl);
            String scheme = parsedUrl.scheme;
            if (this.data.pg == 'html5_inicis') {
              Map<String, String> query = parsedUrl.queryParameters;
              if (query['m_redirect_url'] != null) {
                if (scheme == this.data.appScheme.toLowerCase() &&
                    query['m_redirect_url']!.contains(UrlData.redirectUrl)) {
                  return true;
                }
              }
            }
          }
          return false;
        },
      );
    } else {
      return IamportError(ActionType.payment, validation.getErrorMessage());
    }
  }
}
