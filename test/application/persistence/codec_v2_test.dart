import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regula/application/persistence/construction_codec.dart';
import 'package:regula/application/providers/viewport_provider.dart';
import 'package:regula/domain/construction/construction.dart';
import 'package:regula/domain/construction/document_kernel.dart';
import 'package:regula/domain/construction/geo_object.dart';
import 'package:regula/domain/construction/objects/free_point.dart';
import 'package:regula/domain/construction/objects/midpoint.dart';
import 'package:regula/domain/math/vec2.dart';
import 'package:regula/domain/projective/absolute.dart';
import 'package:regula/domain/projective/complex.dart';

import '../../kitchen_sink.dart';

/// Phase 118: the v2 schema — its version rule and its two hooks.
///
/// Neither hook has a user yet (M-CK owns the kernel, Phase 120 the
/// homogeneous params). What is pinned here is the part that must be
/// settled *before* those users exist: the wire shape, the failure
/// messages, and which documents the version stamp is allowed to lock out
/// of older builds.
void main() {
  // The kernel now rides on the construction rather than on the encode
  // call — a document cannot be written under an absolute other than the
  // one its objects were computed in.
  Map<String, dynamic> encode(Construction construction) => jsonDecode(
    jsonEncode(encodeDocument(construction, viewport: const ViewportState())),
  ) as Map<String, dynamic>;

  group('version stamp', () {
    test('an ordinary document is still written as v1', () {
      // The bump must not lock every existing user out of every document
      // they save from now on. A document using nothing from v2 is
      // readable by a v1 build, so it says so.
      expect(encode(buildKitchenSink())['version'], 1);
      expect(encode(Construction())['version'], 1);
      expect(minimumConstructionFormatVersion, 1);
    });

    test('"version" stays the first key in the file', () {
      // It is computed last; a reader (and a human diffing a save) should
      // not have to find it at the bottom.
      expect(encode(buildKitchenSink()).keys.first, 'version');
    });

    test('a non-default kernel makes the document v2', () {
      final json = encode(
        Construction(
          kernel: const DocumentKernel(metric: FundamentalConic.hyperbolic),
        ),
      );
      expect(json['version'], 2);
      expect(json['kernel'], {'metric': 'hyperbolic'});
    });

    test('a new object kind does not bump it — novelty is not misreading', () {
      // A `FivePointConic` is determined by its five parents, so it stores
      // no params and needs nothing v2 offers. A v1 build meeting one
      // refuses the whole file by its unknown type, which is exactly the
      // protection the stamp buys — so there is nothing left for the stamp
      // to add, and a document that merely *uses a newer kind* must stay
      // openable by every build that understands it.
      final json = encode(buildPostV1Kinds());
      expect(
        (json['objects'] as List).any(
          (o) => (o as Map<String, dynamic>)['type'] == 'FivePointConic',
        ),
        isTrue,
      );
      expect(json['version'], 1);
    });

    test('a homogeneous param makes the document v2', () {
      // No kind emits one yet, so the rule is pinned on the encoded shape
      // directly — the contract a future kind with stored homogeneous
      // state will rely on.
      final json = encode(buildKitchenSink());
      expect(requiredFormatVersion(json), 1);
      ((json['objects'] as List).first as Map<String, dynamic>)['params'] = {
        'lift': encodeHomogeneousParam(const [Complex(1), Complex(2)]),
      };
      expect(requiredFormatVersion(json), 2);
    });

    test('additive keys a v1 reader can safely ignore do not bump it', () {
      // Viewport rotation and the display flags are absent-means-default,
      // so a v1 build reads such a file correctly. Only a key whose
      // absence would be *misread* is worth locking it out for.
      final json = encode(Construction());
      expect(json.containsKey('showAxes'), isTrue);
      expect((json['viewport'] as Map).containsKey('rotation'), isTrue);
      expect(json['version'], 1);
    });
  });

  group('accepted versions', () {
    test('v1, v2 and v3 all decode', () {
      for (final version in [1, 2, 3]) {
        final json = encode(buildKitchenSink())..['version'] = version;
        expect(
          decodeDocument(json).construction.objects,
          hasLength(buildKitchenSink().objects.length),
          reason: 'version $version',
        );
      }
    });

    test('v4 is refused, naming the newest version understood', () {
      final json = encode(Construction())..['version'] = 4;
      expect(
        () => decodeDocument(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('version 4'), contains('latest known: 3')),
          ),
        ),
      );
    });

    test('a version below 1 is refused', () {
      for (final version in [0, -1]) {
        final json = encode(Construction())..['version'] = version;
        expect(
          () => decodeDocument(json),
          throwsA(isA<FormatException>()),
          reason: 'version $version',
        );
      }
    });
  });

  group('kernel block (M-CK hook)', () {
    test('absent means Euclidean — which is what every v1 file is', () {
      final json = encode(buildKitchenSink());
      expect(json.containsKey('kernel'), isFalse);
      expect(decodeDocument(json).kernel, const DocumentKernel());
      expect(decodeDocument(json).kernel.metric, FundamentalConic.euclidean);
    });

    test('an explicit Euclidean kernel round-trips', () {
      final json = encode(Construction())
        ..['kernel'] = <String, dynamic>{'metric': 'euclidean'}
        ..['version'] = 2;
      expect(decodeDocument(json).kernel, const DocumentKernel());
    });

    test('a kernel block without a metric is Euclidean', () {
      final json = encode(Construction())
        ..['kernel'] = <String, dynamic>{}
        ..['version'] = 2;
      expect(decodeDocument(json).kernel, const DocumentKernel());
    });

    // Phase 123: the setting reaches the graph, not just the document
    // record. The absolute is an input to every metric recompute, so a
    // construction that did not carry it would be computing in a geometry
    // the file does not name.
    test('the decoded construction carries the kernel, not just the doc', () {
      final decoded = decodeDocument(encode(buildKitchenSink()));
      expect(decoded.construction.kernel, decoded.kernel);
      expect(decoded.construction.kernel.absolute, Absolute.euclidean);
      expect(decoded.construction.kernel.absolute.isEuclidean, isTrue);
    });

    test('the radius round-trips, and only when it is not 1 (Phase 131)', () {
      final unit = encode(
        Construction(
          kernel: const DocumentKernel(metric: FundamentalConic.hyperbolic),
        ),
      );
      expect(unit['kernel'], <String, dynamic>{
        'metric': 'hyperbolic',
      }, reason: 'a unit-radius document is exactly the v2 file it was');
      expect(unit['version'], 2);

      final sized = encode(
        Construction(
          kernel: const DocumentKernel(
            metric: FundamentalConic.hyperbolic,
            radius: 240,
          ),
        ),
      );
      expect(sized['kernel'], <String, dynamic>{
        'metric': 'hyperbolic',
        'radius': 240.0,
      });
      expect(sized['version'], 3);
      expect(decodeDocument(sized).kernel.radius, 240);
      expect(decodeDocument(sized).construction.kernel.absolute.radius, 240);
    });

    test('a Euclidean kernel never writes a radius, having no scale', () {
      final json = encode(
        Construction(kernel: const DocumentKernel(radius: 17)),
      );
      expect(json.containsKey('kernel'), isFalse);
      expect(json['version'], 1);
    });

    test('a malformed radius is refused, not corrected', () {
      // Same reason an unknown metric is: drawing a document in a plane
      // other than its own is the failure the version stamp was bought to
      // prevent, and a silently clamped radius is that failure with a
      // smaller number on it.
      for (final bad in <Object>['200', 0, -3, double.nan]) {
        final json = encode(Construction())
          ..['kernel'] = <String, dynamic>{
            'metric': 'hyperbolic',
            'radius': bad,
          }
          ..['version'] = 3;
        expect(
          () => decodeDocument(json),
          throwsA(isA<FormatException>()),
          reason: 'radius $bad',
        );
      }
    });

    test('a v3 radius is what a v2 reader would misread, hence the bump', () {
      // The reason this is on the version list at all. A v2 reader skips
      // the key and lands in the right *geometry* — the radius is a chart
      // scale — but reads a figure drawn at radius 240 against the unit
      // disc, where every point of it is outside the plane and the whole
      // document computes undefined. A file that draws as nothing is a
      // misread, not a graceful degradation.
      final construction = Construction(
        kernel: const DocumentKernel(
          metric: FundamentalConic.hyperbolic,
          radius: 240,
        ),
      );
      final a = FreePoint(id: 'a', position: const Vec2(0, 0));
      final b = FreePoint(id: 'b', position: const Vec2(100, 0));
      construction
        ..add(a)
        ..add(b)
        ..add(Midpoint(id: 'm', point1: a, point2: b));
      expect(construction.byId('m')!.isDefined, isTrue);

      final asRead = decodeDocument(
        encode(construction)..['kernel'] = {'metric': 'hyperbolic'},
      );
      expect(
        asRead.construction.byId('m')!.isDefined,
        isFalse,
        reason: 'which is what dropping the key costs',
      );
    });

    test('a fresh construction is Euclidean', () {
      expect(Construction().kernel, const DocumentKernel());
      expect(Construction().kernel.absolute, Absolute.euclidean);
    });

    test('both proper metrics now load, and reach the graph (Phase 126)', () {
      // Was "a reserved but unimplemented metric is refused". The refusal
      // was the honest answer while nothing could draw such a document;
      // lifting it is what M-CK was for. What the refusal was protecting
      // against — a document drawn in a geometry other than its own — is
      // now protected by the thing that actually prevents it: the kernel
      // reaching every recompute and every tool.
      for (final metric in [
        FundamentalConic.hyperbolic,
        FundamentalConic.elliptic,
      ]) {
        final json = encode(Construction())
          ..['kernel'] = <String, dynamic>{'metric': metric.name}
          ..['version'] = 2;
        final decoded = decodeDocument(json);
        expect(decoded.kernel.metric, metric, reason: metric.name);
        expect(
          decoded.construction.kernel.absolute,
          Absolute.of(metric),
          reason: metric.name,
        );
        expect(
          decoded.construction.kernel.absolute.isEuclidean,
          isFalse,
          reason: metric.name,
        );
      }
    });

    test('a non-Euclidean document round-trips through encode', () {
      // The encoder reads the kernel off the construction, so this also
      // pins that a document cannot be written under an absolute other
      // than the one its objects were computed in (Phase 123).
      for (final metric in [
        FundamentalConic.hyperbolic,
        FundamentalConic.elliptic,
      ]) {
        final construction = Construction(
          kernel: DocumentKernel(metric: metric),
        );
        final a = FreePoint(id: 'a', position: const Vec2(0, 0));
        final b = FreePoint(id: 'b', position: const Vec2(0.8, 0));
        construction
          ..add(a)
          ..add(b)
          ..add(Midpoint(id: 'm', point1: a, point2: b));

        final json = encode(construction);
        expect(json['version'], 2, reason: metric.name);
        expect(
          (json['kernel']! as Map<String, dynamic>)['metric'],
          metric.name,
          reason: metric.name,
        );

        final decoded = decodeDocument(json);
        expect(decoded.construction.kernel.metric, metric, reason: metric.name);
        // And the geometry came back with it: the CK midpoint of
        // (0,0)–(0.8,0) is not the affine 0.4.
        final m = decoded.construction.byId('m')! as GeoPoint;
        final original = construction.byId('m')! as GeoPoint;
        expect(m.position!.x, closeTo(original.position!.x, 1e-12));
        expect(m.position!.x, isNot(closeTo(0.4, 1e-6)), reason: metric.name);
      }
    });

    test('an unknown metric name is refused', () {
      final json = encode(Construction())
        ..['kernel'] = <String, dynamic>{'metric': 'minkowski'}
        ..['version'] = 2;
      expect(
        () => decodeDocument(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('minkowski'),
          ),
        ),
      );
    });

    test('a malformed kernel block is a FormatException, not a TypeError', () {
      for (final bad in <Object>[
        'euclidean',
        42,
        <Object>[],
        <String, dynamic>{'metric': 7},
      ]) {
        final json = encode(Construction())
          ..['kernel'] = bad
          ..['version'] = 2;
        expect(
          () => decodeDocument(json),
          throwsA(isA<FormatException>()),
          reason: '$bad',
        );
      }
    });

    test('every reserved metric name is distinct and stable', () {
      expect(FundamentalConic.values.map((m) => m.name), [
        'euclidean',
        'hyperbolic',
        'elliptic',
      ]);
      for (final metric in FundamentalConic.values) {
        expect(FundamentalConic.byName(metric.name), metric);
      }
      expect(FundamentalConic.byName('Euclidean'), isNull);
    });
  });

  group('homogeneous params (Phase 120 hook)', () {
    const triple = [Complex(1.5, -2.25), Complex(0, 3), Complex(-7, 0)];

    test('round-trips component for component, through JSON', () {
      final params = jsonDecode(
        jsonEncode({'p': encodeHomogeneousParam(triple)}),
      ) as Map<String, dynamic>;
      expect(homogeneousParam('x', params, 'p', length: 3), triple);
    });

    test('a real component survives as exactly real', () {
      // The shape writes [re, im] even for real values precisely so that
      // nothing has to guess later whether a bare number was real.
      final params = {
        'p': encodeHomogeneousParam(const [Complex(2), Complex(0), Complex(1)]),
      };
      final decoded = homogeneousParam('x', params, 'p', length: 3);
      expect(decoded.every((c) => c.im == 0), isTrue);
      expect(decoded[0].re, 2.0);
    });

    test('any length works — a point, a line, a conic\'s six entries', () {
      for (final length in [3, 6]) {
        final values = [
          for (var i = 0; i < length; i++) Complex(i.toDouble(), -i.toDouble()),
        ];
        final params = {'p': encodeHomogeneousParam(values)};
        expect(homogeneousParam('x', params, 'p', length: length), values);
      }
    });

    test('a wrong length is refused', () {
      final params = {'p': encodeHomogeneousParam(triple)};
      expect(
        () => homogeneousParam('x', params, 'p', length: 6),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"x"'), contains('6 homogeneous components')),
          ),
        ),
      );
    });

    test('an absent or non-homogeneous param is refused', () {
      for (final params in <Map<String, dynamic>>[
        {},
        {'p': 1.0},
        {'p': <Object>[]},
        {
          'p': <String, dynamic>{'wrong': <Object>[]},
        },
      ]) {
        expect(
          () => homogeneousParam('x', params, 'p', length: 3),
          throwsA(isA<FormatException>()),
          reason: '$params',
        );
      }
    });

    test('a malformed component is a FormatException, not a TypeError', () {
      for (final components in <Object>[
        [
          [1, 0],
          [2, 0],
          [3],
        ],
        [
          [1, 0],
          [2, 0],
          ['x', 0],
        ],
        [
          [1, 0],
          [2, 0],
          3,
        ],
      ]) {
        expect(
          () => homogeneousParam(
            'x',
            {
              'p': <String, dynamic>{'h': components},
            },
            'p',
            length: 3,
          ),
          throwsA(isA<FormatException>()),
          reason: '$components',
        );
      }
    });
  });
}
