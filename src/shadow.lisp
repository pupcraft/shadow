(in-package :shadow)

(defclass state ()
  ((%programs :reader programs
              :initform (au:dict #'eq))
   (%blocks :reader blocks
            :initform (au:dict #'eq :bindings (au:dict #'eq :uniform (au:dict) :buffer (au:dict))
                                    :aliases (au:dict #'equalp)))
   (%track-dependencies-p :reader track-dependencies-p
                          :initform nil)
   (%dependencies :reader dependencies
                  :initform (au:dict #'eq
                                     :fn->deps (au:dict #'equal)
                                     :dep->fns (au:dict #'equal)
                                     :stage-fn->programs (au:dict #'equal)))
   (%modify-hook :accessor modify-hook
                 :initform (constantly nil))
   (%buffers :reader buffers
             :initform (au:dict #'eq))))

(defvar *state* (make-instance 'state))

(defun enable-dependency-tracking ()
  (setf (slot-value *state* '%track-dependencies-p) t))

(defun disable-dependency-tracking ()
  (setf (slot-value *state* '%track-dependencies-p) nil))

(defun store-source (program stage)
  (let ((source (varjo:glsl-code stage)))
    (setf (au:href (source program) (stage-type stage))
          (subseq source (1+ (position #\newline source)) (- (length source) 2)))))

(defmacro define-struct (name &body slots)
  "Define a GPU structure."
  `(varjo:define-vari-struct ,name () ,@slots))

(defmacro define-macro (name lambda-list &body body)
  "Define a GPU macro."
  `(varjo:define-vari-macro ,name ,lambda-list ,@body))
