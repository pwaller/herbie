#lang racket

(require racket/pretty)
(require "datafile.rkt")
(require "../common.rkt")
(require "../points.rkt")
(require "../matcher.rkt")
(require "../alternative.rkt")
(require "../test.rkt")
(require "../infer-regimes.rkt")
(require "../programs.rkt")
(require "../plot.rkt")
(require "../compile/texify.rkt")

(provide make-graph make-traceback make-timeout)

;; TODO: Move to a common file
(define (format-time ms)
  (cond
   [(< ms 1000) (format "~a ms" (round ms))]
   [(< ms 60000) (format "~a s" (/ (round (/ ms 100.0)) 10))]
   [(< ms 3600000) (format "~a m" (/ (round (/ ms 6000.0)) 10))]
   [else (format "~a hr" (/ (round (/ ms 360000.0)) 10))]))

(define (display-bits r #:sign [sign #f])
  (cond
   [(not r) ""]
   [(and (r . > . 0) sign) (format "+~a" (/ (round (* r 10)) 10))]
   [else (format "~a" (/ (round (* r 10)) 10))]))


(define (make-graph result profile?)
  (match result
    [(test-result test rdir time bits start-alt end-alt points exacts
                  start-est-error end-est-error newpoints newexacts start-error end-error target-error)
     (printf "<!doctype html>\n")
     (printf "<html>\n")
     (printf "<head>")
     (printf "<meta charset='utf-8' />")
     (printf "<title>Results for ~a</title>" (test-name test))
     (printf "<link rel='stylesheet' type='text/css' href='../graph.css' />")
     (printf "<script src='~a'></script>" ; MathJax URL for prettifying programs
             "https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML")
     (printf "</head>\n")
     (printf "<body>\n")

     ; Big bold numbers
     (printf "<div id='large'>\n")
     (printf "<div>Time: <span class='number'>~a</span></div>\n"
             (format-time time))
     (printf "<div>Input Error: <span class='number'>~a</span></div>\n"
             (display-bits (errors-score start-error)))
     (printf "<div>Output Error: <span class='number'>~a</span></div>\n"
             (display-bits (errors-score end-error)))
     (printf "<div>Bits: <span class='number'>~a</span></div>\n"
             bits)
     (printf "</div>\n")

     (printf "<div id='summary'>\n")
     (printf "<div><div class='formula'>\\(~a\\)</div>Input</div>\n"
             (texify-expression (program-body (alt-program start-alt))))
     (printf "<div><div class='formula'>\\(~a\\)</div>Output</div>\n"
             (texify-expression (program-body (alt-program end-alt))))
     (printf "</div>\n")

     (printf "<dl id='about'>\n")
     (printf "<dt>Test:</dt><dd>~a</dd>" (test-name test))
     (printf "<dt>Logs:</dt>")
     (printf "<dd><a href='debug.txt'>Debug output</a>")
     (when profile?
       (printf ", <a href='profile.txt'>Profiling report</a>"))
     (printf "</dd>\n")
     (printf "<dt>Bits:</dt><dd>~a bits</dd>\n" bits)
     (printf "</dl>\n")

     (printf "<div id='graphs'>\n")
     (for ([var (test-vars test)] [idx (in-naturals)])
       (call-with-output-file (build-path report-output-path rdir (format "plot-~a.png" idx)) #:exists 'replace
                              (lambda (out)
                                (herbie-plot #:port out #:kind 'png
                                             (reap [sow]
                                                   (sow (error-points start-error newpoints #:axis idx #:color *red-theme*))
                                                   (when target-error
                                                     (sow (error-points target-error newpoints #:axis idx #:color *green-theme*)))
                                                   (sow (error-points end-error newpoints #:axis idx #:color *blue-theme*))

                                                   (sow (error-avg start-error newpoints #:axis idx #:color *red-theme*))
                                                   (when target-error
                                                     (sow (error-avg target-error newpoints #:axis idx #:color *green-theme*)))
                                                   (sow (error-avg end-error newpoints #:axis idx #:color *blue-theme*))))
                                (printf "<img width='400' height='200' src='plot-~a.png' />\n" idx))))
     (printf "</div>\n")
     
     (printf "<ol id='process-info'>\n")
     (output-history end-alt)
     (printf "</ol>\n")

     (printf "</body>\n")
     (printf "</html>\n")]))

(define (make-traceback result profile?)
  (match result
    [(test-failure test bits exn time rdir)
     (printf "<!doctype html>\n")
     (printf "<html>\n")
     (printf "<head>\n")
     (printf "<meta charset='utf-8' />\n")
     (printf "<title>Exception for ~a</title>" (test-name test))
     (printf "<link rel='stylesheet' type='text/css' href='../graph.css' />")
     (printf "</head>")
     (printf "<body>\n")
                   
     (printf "<dl id='about'>\n")
     (printf "<dt>Test:</dt><dd>~a</dd>" (test-name test))
     (printf "<dt>Logs:</dt>")
     (printf "<dd><a href='debug.txt'>Debug output</a>")
     (when profile?
       (printf ", <a href='profile.txt'>Profiling report</a>"))
     (printf "</dd>\n")
     (printf "<dt>Bits:</dt><dd>~a bits</dd>\n" bits)
     (printf "</dl>\n")

     (printf "<h2 id='error-message'>~a</h2>\n" (html-escape-unsafe (exn-message exn)))
     (printf "<ol id='traceback'>\n")
     (for ([tb (continuation-mark-set->context (exn-continuation-marks exn))])
       (printf "<li><code>~a</code> in <code>~a</code></li>\n"
               (html-escape-unsafe (~a (car tb))) (srcloc->string (cdr tb))))
     (printf "</ol>\n")

     (printf "</body>\n")
     (printf "</html>\n")]))

(define (make-timeout result profile?)
  (match result
    [(test-timeout test bits rdir)
     (printf "<!doctype html>\n")
     (printf "<html>\n")
     (printf "<head>\n")
     (printf "<meta charset='utf-8' />\n")
     (printf "<title>Timeout for ~a</title>" (test-name test))
     (printf "<link rel='stylesheet' type='text/css' href='../graph.css' />")
     (printf "</head>")
     (printf "<body>\n")

     (printf "<dl id='about'>\n")
     (printf "<dt>Test:</dt><dd>~a</dd>" (test-name test))
     (printf "<dt>Logs:</dt>")
     (printf "<dd><a href='debug.txt'>Debug output</a>")
     (when profile?
       (printf ", <a href='profile.txt'>Profiling report</a>"))
     (printf "</dd>\n")
     (printf "<dt>Bits:</dt><dd>~a bits</dd>\n" bits)
     (printf "</dl>\n")

     (printf "<h2>Test timed out</h2>\n")

     (printf "</body>\n")
     (printf "</html>\n")]))

(struct interval (alt-idx start-point end-point expr))

(define (output-history altn)
  (match altn
    [(alt-event _ 'start _)
     (printf "<li>Started with <code><pre>~a</pre></code></li>\n"
             (pretty-format (alt-program altn) 65))]

    [(alt-event prog `(start ,strategy) `(,prev))
     (output-history prev)
     (printf "<li class='event'>Using strategy <code>~a</code></li>\n" strategy)]

    [(alt-event _ `(regimes ,splitpoints) prevs)
     (let* ([start-sps (cons (sp -1 -1 -inf.0) (take splitpoints (sub1 (length splitpoints))))]
            [vars (program-variables (alt-program altn))]
            [intervals
             (for/list ([start-sp start-sps] [end-sp splitpoints])
               (interval (sp-cidx end-sp) (sp-point start-sp) (sp-point end-sp) (sp-bexpr end-sp)))]
            [interval->string
             (λ (ival)
                (format "~a < ~a < ~a" (interval-start-point ival)
                        (interval-expr ival) (interval-end-point ival)))])
       (for/list ([entry prevs] [entry-idx (range (length prevs))])
         (let* ([entry-ivals
                 (filter (λ (intrvl) (= (interval-alt-idx intrvl) entry-idx)) intervals)]
                [condition
                 (string-join (map interval->string entry-ivals) " or ")])
           (printf "<h2><code>if <span class='condition'>~a</span></code></h2>\n" condition)
           (printf "<ol>\n")
           (output-history entry)
           (printf "</ol>\n"))))]

    [(alt-event prog `(taylor ,pt ,loc) `(,prev))
     (output-history prev)
     (printf "<li>Taylor expanded <code><pre>~a</pre></code>"
             (location-get loc (alt-program prev)))
     (printf "around ~a to get <code><pre>~a</pre></code></li>" pt (pretty-format prog 65))]

    [(alt-event prog 'periodicity `(,base ,subs ...))
     (output-history base)
     (for ([sub subs])
       (printf "<hr/><li class='event'>Optimizing periodic subexpression</li>\n")
       (output-history sub))
     (printf "<hr/><li class='event'>Combined periodic subexpressions</li>\n")]

    [(alt-event prog 'removed-pows `(,alt))
     (output-history alt)
     (printf "<hr/><li class='event'>Removed slow pow expressions</li>\n")]

    [(alt-event prog 'final-simplify `(,alt))
     (output-history alt)
     (printf "<hr/><li class='event'>Applied final simplification</li>\n")]

    [(alt-delta prog cng prev)
     (output-history prev)
     (printf "<li>Applied <span class='rule'>~a</span> "
             (rule-name (change-rule cng)))
     (printf "to get <code><pre>~a</pre></code></li>\n"
             (pretty-format prog 65))]))

(define (html-escape-unsafe err)
  (string-replace (string-replace (string-replace err "&" "&amp;") "<" "&lt;") ">" "&gt;"))

(define (srcloc->string sl)
  (if sl
      (string-append
       (path->string (srcloc-source sl))
       ":"
       (number->string (srcloc-line sl))
       ":"
       (number->string (srcloc-column sl)))
      "???"))