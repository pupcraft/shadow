(in-package :shadow)

(defvar *shader-info*)

(defclass shader-info ()
  ((%programs :reader programs
              :initform (au:dict #'eq))
   (%block-bindings :reader block-bindings
                    :initform (au:dict #'eq :uniform (au:dict) :buffer (au:dict)))
   (%function-table :reader function-table
                    :initform (au:dict #'equal))
   (%buffers :reader buffers
             :initform (au:dict #'eq))))

(defun initialize-shaders ()
  "Initialize the shaders."
  (setf *shader-info* (make-instance 'shader-info)))

(defun find-gpu-function (func-spec)
  (destructuring-bind (name . types) func-spec
    (find types (varjo.internals::get-external-function-by-name name nil)
          :key (lambda (x) (mapcar #'second (varjo.internals:in-args x)))
          :test #'equal)))

(defun get-function-spec (function)
  (cons (varjo:name function) (mapcar #'second (varjo.internals:in-args function))))

(defun stage-type (stage)
  (varjo.internals::stage-obj-to-name stage))

(defun stage-type->shader-type (stage-type)
  (ecase stage-type
    (:vertex :vertex-shader)
    (:tessellation-control :tess-control-shader)
    (:tessellation-evaluation :tess-evaluation-shader)
    (:geometry :geometry-shader)
    (:fragment :fragment-shader)
    (:compute :compute-shader)))

(defun make-stage (version primitive stage-spec)
  (destructuring-bind (stage-type (&key (version version)) func-spec) stage-spec
    (let ((func (find-gpu-function func-spec)))
      (varjo:make-stage
       stage-type
       (varjo.internals:in-args func)
       (varjo.internals:uniforms func)
       `(,(ensure-keyword version))
       (varjo.internals:code func)
       t
       (when (eq stage-type :vertex)
         (varjo.internals:primitive-name-to-instance primitive))))))

(defun translate-stages (version primitive stage-specs)
  (varjo:rolling-translate
   (mapcar
    (lambda (x) (make-stage version primitive x))
    stage-specs)))

(defun store-source (program stage)
  (let ((source (varjo:glsl-code stage)))
    (setf (au:href (source program) (stage-type stage))
          (subseq source (1+ (position #\newline source)) (- (length source) 2)))))

(defmacro defstruct-gpu (name context &body slots)
  "Define a GPU structure."
  `(varjo:v-defstruct ,name ,context ,@slots))

(defmacro defun-gpu (name args &body body)
  "Define a GPU function."
  (au:with-unique-names (split-details fn used-fns)
    (let ((split-args (varjo.utils:split-arguments args '(&uniform &context))))
      (destructuring-bind (in-args uniforms context) split-args
        `(let* ((,split-details (varjo:test-translate-function-split-details
                                 ',name ',in-args ',uniforms ',context ',body))
                (,fn (varjo:add-external-function ',name ',in-args ',uniforms ',body))
                (,used-fns (varjo:used-external-functions (first ,split-details))))
           (symbol-macrolet ((fn-deps (au:href (function-table *shader-info*)
                                               (get-function-spec ,fn))))
             (setf fn-deps nil)
             (dolist (dep ,used-fns)
               (pushnew (get-function-spec dep) fn-deps)))
           ,fn)))))
